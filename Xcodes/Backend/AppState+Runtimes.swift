import Foundation
import XcodesKit
import OSLog
import Path
import Version

extension AppState {
    func updateDownloadableRuntimes() {
        downloadableRuntimesTask?.cancel()
        let taskID = UUID()
        downloadableRuntimesTaskID = taskID
        downloadableRuntimesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.downloadableRuntimesTaskID == taskID {
                    self.downloadableRuntimesTask = nil
                    self.downloadableRuntimesTaskID = nil
                }
            }
            do {
                var store = self.runtimeListStore
                let runtimes = try await store.updateDownloadableRuntimes()
                try Task.checkCancellation()

                let activeStates: [String: RuntimeInstallState] = Dictionary(self.downloadableRuntimes.compactMap { runtime in
                    self.runtimeTasks[runtime.identifier] == nil ? nil : (runtime.identifier, runtime.installState)
                }, uniquingKeysWith: { existing, _ in existing })
                self.downloadableRuntimes = runtimes.map { runtime in
                    var runtime = runtime
                    runtime.installState = activeStates[runtime.identifier] ?? runtime.installState
                    return runtime
                }
            } catch is CancellationError {
            } catch {
                Logger.appState.error("Error downloading runtimes: \(error.localizedDescription)")
            }
        }
    }

    func updateInstalledRuntimes() {
        installedRuntimesTask?.cancel()
        let taskID = UUID()
        installedRuntimesTaskID = taskID
        installedRuntimesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.installedRuntimesTaskID == taskID {
                    self.installedRuntimesTask = nil
                    self.installedRuntimesTaskID = nil
                }
            }
            do {
                Logger.appState.info("Loading Installed runtimes")
                let runtimes = try await self.runtimeService.localInstalledRuntimes()
                try Task.checkCancellation()

                self.installedRuntimes = runtimes
            } catch is CancellationError {
            } catch {
                Logger.appState.error("Error loading installed runtimes: \(error.localizedDescription)")
            }
        }
    }

    private func installRuntime(_ runtime: DownloadableRuntime, for xcodeID: XcodeID?, taskID: UUID) async throws {
        if runtime.contentType == .diskImage {
            let archiveURL = try await downloadRuntimeArchive(runtime: runtime, taskID: taskID)
            let xcode = try await xcodeForRuntime(runtime, preferredID: xcodeID)
            let developerDirectory = xcode.selected ? nil : xcode.developerDirectory
            try await runtimeArchiveInstallService(developerDirectory: developerDirectory).install(
                runtime: runtime,
                archiveURL: archiveURL,
                stepChanged: { step in
                    await self.setRuntimeStep(step, runtime: runtime, taskID: taskID, postNotification: true)
                }
            )
        } else {
            let preferredInstall = xcodeID.flatMap { installationTasks[$0] }
            let xcode = try await xcodeForRuntime(runtime, preferredID: xcodeID)
            let method = try RuntimeInstallPolicy().installMethod(for: runtime, selectedXcodeVersion: xcode.version)
            guard case let .xcodebuild(architecture) = method else {
                throw XcodesKitError("This simulator runtime format is unsupported.")
            }
            do {
                try await installRuntimeWithXcodebuild(
                    runtime, architecture: architecture,
                    developerDirectory: xcode.selected ? nil : xcode.developerDirectory, taskID: taskID
                )
            } catch let error as ProcessExecutionError {
                // A parallel attempt may have used a different Xcode. Retry once with the
                // requested Xcode if it was still installing when the download began.
                try Task.checkCancellation()
                guard let xcodeID, xcodeID != xcode.id, let preferredInstall else { throw error }
                try await waitForXcodeInstall(preferredInstall, runtime: runtime)
                guard let preferred = allXcodes.first(where: { $0.id == xcodeID }),
                      preferred.installState.installed,
                      (try? RuntimeInstallPolicy().installMethod(for: runtime, selectedXcodeVersion: preferred.version)) == method,
                      let directory = preferred.developerDirectory else { throw error }
                try await installRuntimeWithXcodebuild(
                    runtime, architecture: architecture, developerDirectory: directory, taskID: taskID
                )
            }
        }
    }

    private func xcodeForRuntime(_ runtime: DownloadableRuntime, preferredID: XcodeID?) async throws -> Xcode {
        try Task.checkCancellation()
        let policy = RuntimeInstallPolicy()
        func compatible(_ xcode: Xcode) -> Bool {
            (try? policy.installMethod(for: runtime, selectedXcodeVersion: xcode.version)) != nil
        }
        func installedXcode() -> Xcode? {
            let installed = allXcodes.filter {
                $0.installState.installed && installationTasks[$0.id] == nil && compatible($0)
            }
            return installed.first { $0.id == preferredID }
                ?? installed.first { xcode in
                    xcode.platformSDKBuilds.contains { runtime.sdkBuildUpdate?.contains($0) == true }
                }
                ?? installed.first(where: \.selected)
                ?? installed.max { $0.version < $1.version }
        }

        let available = installedXcode()
        if runtime.betaNumber != nil, let preferredID, let task = installationTasks[preferredID],
           available?.id != preferredID,
           available?.platformSDKBuilds.contains(where: { runtime.sdkBuildUpdate?.contains($0) == true }) != true {
            // A toolchain that meets the platform minimum can still stall on a newer beta asset.
            try await waitForXcodeInstall(task, runtime: runtime)
            guard let xcode = installedXcode(), xcode.id == preferredID else {
                throw XcodesKitError(localizeString("Xcode installation did not finish. Install Xcode and try this simulator runtime again."))
            }
            return xcode
        }
        if let available { return available }

        let pending = allXcodes.filter { installationTasks[$0.id] != nil && compatible($0) }
        if let xcode = pending.first(where: { $0.id == preferredID }) ?? pending.max(by: { $0.version < $1.version }),
           let task = installationTasks[xcode.id] {
            try await waitForXcodeInstall(task, runtime: runtime)
            if let xcode = installedXcode() { return xcode }
            throw XcodesKitError(localizeString("Xcode installation did not finish. Install Xcode and try this simulator runtime again."))
        }

        _ = try policy.installMethod(for: runtime, selectedXcodeVersion: allXcodes.first(where: \.selected)?.version)
        throw RuntimeInstallPolicyError.noSelectedXcode
    }

    private func waitForXcodeInstall(_ task: Task<Void, Never>, runtime: DownloadableRuntime) async throws {
        waitingForXcodeRuntimes.insert(runtime.identifier)
        await task.value
        try Task.checkCancellation()
        waitingForXcodeRuntimes.remove(runtime.identifier)
    }

    private func installRuntimeWithXcodebuild(
        _ runtime: DownloadableRuntime,
        architecture: String?,
        developerDirectory: String?,
        taskID: UUID
    ) async throws {
        setRuntimeStep(.downloading(progress: Progress(totalUnitCount: 100)), runtime: runtime, taskID: taskID)
        let download = Current.shell.downloadRuntime
        try await RuntimeXcodebuildInstallService(download: { platform, build, architecture in
            download(platform, build, architecture, developerDirectory)
        }).downloadAndInstall(runtime: runtime, architecture: architecture) { progress in
            Task { @MainActor [weak self] in
                let step: RuntimeInstallationStep = progress.isIndeterminate ? .installing : .downloading(progress: progress)
                self?.setRuntimeStep(step, runtime: runtime, taskID: taskID)
            }
        }
    }

    private func setRuntimeStep(
        _ step: RuntimeInstallationStep,
        runtime: DownloadableRuntime,
        taskID: UUID,
        postNotification: Bool = false
    ) {
        guard runtimeTaskIDs[runtime.identifier] == taskID else { return }
        setInstallationStep(of: runtime, to: step, postNotification: postNotification)
    }

    func downloadRuntime(runtime: DownloadableRuntime, for xcodeID: XcodeID? = nil) {
        let id = runtime.identifier
        guard runtimeTasks[id] == nil, !isRemovingRuntime(runtime) else { return }

        let taskID = UUID()
        runtimeTaskIDs[id] = taskID
        setInstallationStep(of: runtime, to: .downloading(progress: Progress(totalUnitCount: 100)), postNotification: false)
        runtimeTasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.runtimeTaskIDs[id] == taskID {
                    self.waitingForXcodeRuntimes.remove(id)
                    self.runtimeTasks[id] = nil
                    self.runtimeTaskIDs[id] = nil
                }
            }
            do {
                try Task.checkCancellation()
                try await self.installRuntime(runtime, for: xcodeID, taskID: taskID)
                try Task.checkCancellation()
                if let index = self.downloadableRuntimes.firstIndex(where: { $0.identifier == id }) {
                    self.downloadableRuntimes[index].installState = .installed
                }
                self.updateInstalledRuntimes()
            } catch {
                guard !Task.isCancelled, self.runtimeTaskIDs[id] == taskID else { return }
                if let index = self.downloadableRuntimes.firstIndex(where: { $0.identifier == id }) {
                    self.downloadableRuntimes[index].installState = .notInstalled
                }
                self.presentRuntimeInstallError(error, runtime: runtime)
            }
        }
    }

    private func presentRuntimeInstallError(_ error: Error, runtime: DownloadableRuntime) {
        self.error = error
        let message: String
        switch error {
        case let error as ProcessExecutionError:
            Logger.appState.error("Simulator runtime command exited with status \(error.terminationStatus): \(error.standardError, privacy: .public)")
            message = error.runtimeFailureMessage
        case let error as RuntimeInstallPolicyError:
            switch error {
            case .noSelectedXcode:
                message = localizeString("Install a compatible version of Xcode, then try installing this simulator runtime again.")
            case .xcode16_1OrGreaterRequired:
                message = localizeString("Alert.Install.Error.Need.Xcode16.1")
            case .xcode26OrGreaterRequired:
                message = localizeString("Alert.Install.Error.Need.Xcode26")
            }
        case let error as XcodesKitError:
            message = error.message
        default:
            message = error.legibleLocalizedDescription
        }
        presentedAlert = .generic(title: localizeString("Unable to install simulator runtime"),
                                  message: runtime.visibleIdentifier + "\n\n" + message)
    }

    func downloadRuntimeArchive(runtime: DownloadableRuntime, taskID: UUID? = nil) async throws -> URL {
        let downloader = Downloader(rawValue: Current.defaults.string(forKey: "downloader") ?? "aria2") ?? .aria2

        Logger.appState.info("Downloading \(runtime.visibleIdentifier) with \(downloader)")
        let archiveURL = try await runtimeArchiveService().archiveURL(
            for: runtime,
            destinationDirectory: .xcodesApplicationSupport,
            downloader: downloader
        ) { [weak self] progress in
            let expectedTaskID = taskID
            Task { @MainActor [weak self] in
                if let expectedTaskID, self?.runtimeTaskIDs[runtime.identifier] != expectedTaskID {
                    return
                }
                self?.setInstallationStep(of: runtime, to: .downloading(progress: progress), postNotification: false)
            }
        }
        Logger.appState.info("Using runtime archive at \(archiveURL.path).")
        return archiveURL
    }

    private func runtimeArchiveService() -> RuntimeArchiveService {
        RuntimeArchiveService(
            fileExists: { Current.files.fileExistsAtPath($0.string) },
            download: { runtime, url, destination, downloader, progressChanged in
                let archiveURL = try await self.runtimeArchiveDownloadStrategyService.download(
                    runtime: runtime,
                    url: url,
                    destination: destination,
                    downloader: downloader,
                    progressChanged: progressChanged
                )
                Logger.appState.debug("Done downloading runtime")
                return archiveURL
            }
        )
    }

    private var runtimeArchiveDownloadStrategyService: RuntimeArchiveDownloadStrategyService {
        RuntimeArchiveDownloadStrategyService(
            validateDownloadPath: { path in
                // Validating the ADC path sets the session cookie required for runtime downloads.
                try await self.validateADCSession(path: path)
            },
            aria2Path: { Path(url: Bundle.main.url(forAuxiliaryExecutable: "aria2c")!)! },
            cookiesForURL: { Current.network.session.configuration.httpCookieStorage?.cookies(for: $0) ?? [] }
        )
    }

    private func runtimeArchiveInstallService(developerDirectory: String?) -> RuntimeArchiveInstallService {
        let runtimeService = self.runtimeService
        return RuntimeArchiveInstallService(
            installDiskImage: { url in
                guard let developerDirectory else {
                    try await runtimeService.installRuntimeImage(dmgURL: url)
                    return
                }
                _ = try await Process.runAsync(URL(fileURLWithPath: "/usr/bin/env"), [
                    "DEVELOPER_DIR=\(developerDirectory)", "/usr/bin/xcrun", "simctl", "runtime", "add", url.path
                ])
            },
            removeArchive: { url in
                try Current.files.removeItem(at: url)
            }
        )
    }

    public func installFromImage(dmgURL: URL) async throws {
        try await self.runtimeService.installRuntimeImage(dmgURL: dmgURL)
    }

    func cancelRuntimeInstall(runtime: DownloadableRuntime) {
        runtimeTasks[runtime.identifier]?.cancel()
        runtimeTasks[runtime.identifier] = nil
        runtimeTaskIDs[runtime.identifier] = nil
        waitingForXcodeRuntimes.remove(runtime.identifier)

        ArchiveCancellationCleanupService(
            removeItem: { try Current.files.removeItem(at: $0) }
        ).cleanupRuntimeArchive(
            for: runtime,
            destinationDirectory: .xcodesApplicationSupport
        )

        guard let index = self.downloadableRuntimes.firstIndex(where: { $0.identifier == runtime.identifier }) else { return }
        self.downloadableRuntimes[index].installState = .notInstalled

        updateInstalledRuntimes()
    }

    func runtimeInstallPath(xcode: Xcode, runtime: DownloadableRuntime) -> Path? {
        RuntimeInstallationLookupService()
            .installPath(for: runtime, in: installedRuntimes)
    }

    func coreSimulatorInfo(runtime: DownloadableRuntime) -> CoreSimulatorImage? {
        RuntimeInstallationLookupService()
            .coreSimulatorImage(for: runtime, in: installedRuntimes)
    }

    func isRemovingRuntime(_ runtime: DownloadableRuntime) -> Bool {
        guard let image = coreSimulatorInfo(runtime: runtime) else { return false }
        return removingRuntimeImages.contains(image.uuid.uppercased())
    }

    func deleteRuntime(runtime: DownloadableRuntime, using xcodePath: Path? = nil) async throws {
        guard let info = coreSimulatorInfo(runtime: runtime) else {
            throw XcodesKitError("No simulator found with \(runtime.identifier)")
        }

        let imageID = info.uuid.uppercased()
        guard removingRuntimeImages.insert(imageID).inserted else {
            throw XcodesKitError(localizeString("This simulator runtime is being removed."))
        }
        defer { removingRuntimeImages.remove(imageID) }

        do {
            try await requestRuntimeRemoval(identifier: info.uuid, using: xcodePath)
        } catch {
            guard Self.isRuntimeRemovalInProgress(runtimeDeletionErrorMessage(error)) else { throw error }
        }

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(210)
        while clock.now < deadline {
            try Task.checkCancellation()
            if let inventory = try? await runtimeService.localInstalledRuntimes(),
               !inventory.contains(where: { $0.uuid.uppercased() == imageID }) {
                installedRuntimes.removeAll { $0.uuid.uppercased() == imageID }
                updateInstalledRuntimes()
                if let index = downloadableRuntimes.firstIndex(where: { $0.identifier == runtime.identifier }),
                   downloadableRuntimes[index].installState == .installed {
                    downloadableRuntimes[index].installState = .notInstalled
                }
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw XcodesKitError(localizeString("CoreSimulator is still removing this runtime. Try again if it remains installed."))
    }

    static func isRuntimeRemovalInProgress(_ message: String) -> Bool {
        message.contains("com.apple.CoreSimulator.simdiskimaged.SimDiskImageError")
            && message.contains("code=24)")
            && message.localizedCaseInsensitiveContains("Attempting to delete image")
    }

    private func requestRuntimeRemoval(identifier: String, using xcodePath: Path?) async throws {
        if let xcodePath {
            try await deleteRuntime(identifier: identifier, using: xcodePath)
        } else {
            do {
                try await runtimeService.deleteRuntime(identifier: identifier)
            } catch {
                guard Self.isMissingDeveloperToolError(runtimeDeletionErrorMessage(error)),
                      let path = newestInstalledXcode()?.installedPath else { throw error }
                try await deleteRuntime(identifier: identifier, using: path)
            }
        }
    }

    private func deleteRuntime(identifier: String, using xcodePath: Path) async throws {
        let developerDirectory = xcodePath.url.appendingPathComponent("Contents/Developer").path
        try await Current.shell.deleteRuntimeWithDeveloperDirectory(identifier, developerDirectory)
    }

    func newestInstalledXcode(excluding id: XcodeID? = nil) -> Xcode? {
        allXcodes.filter { $0.id != id && $0.installState.installed }.max { $0.version < $1.version }
    }

    func removeRuntimesForUninstall(_ runtimes: [DownloadableRuntime], using path: Path) async -> Bool {
        for runtime in runtimes where coreSimulatorInfo(runtime: runtime) != nil {
            do {
                try Task.checkCancellation()
                try await deleteRuntime(runtime: runtime, using: path)
            } catch is CancellationError {
                return false
            } catch {
                presentRuntimeDeletionError(error, runtime: runtime, inSettings: false)
                return false
            }
        }
        return true
    }

    /// - Parameter presentErrorInSettings: Show failures in the Settings window (Platforms list) instead of the main window.
    func confirmDeleteRuntime(runtime: DownloadableRuntime, presentErrorInSettings: Bool = true) {
        guard deleteRuntimeTask == nil, !isRemovingRuntime(runtime) else { return }
        let taskID = UUID()
        deleteRuntimeTaskID = taskID
        deleteRuntimeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.deleteRuntimeTaskID == taskID {
                    self.deleteRuntimeTask = nil
                    self.deleteRuntimeTaskID = nil
                }
            }

            do {
                try await self.deleteRuntime(runtime: runtime)
            } catch is CancellationError {
            } catch {
                guard self.deleteRuntimeTaskID == taskID else { return }
                self.presentRuntimeDeletionError(error, runtime: runtime, inSettings: presentErrorInSettings)
            }
        }
    }

    /// Shows why a platform couldn't be removed. When it failed because no Xcode is active,
    /// offers to make the newest installed release active and try again.
    func presentRuntimeDeletionError(_ error: Error, runtime: DownloadableRuntime, inSettings: Bool) {
        let message = runtimeDeletionErrorMessage(error)
        if Self.isMissingDeveloperToolError(message) {
            if inSettings {
                presentedPreferenceAlert = .noActiveXcode(runtime: runtime, xcode: latestInstalledReleaseXcode)
            } else {
                presentedAlert = .noActiveXcode(runtime: runtime, xcode: latestInstalledReleaseXcode)
            }
        } else if inSettings {
            presentedPreferenceAlert = .generic(title: "Error", message: message)
        } else {
            presentedAlert = .generic(title: "Error", message: message)
        }
    }

    /// `xcrun` reports this when the active developer directory is the Command Line Tools,
    /// which don't include `simctl`.
    static func isMissingDeveloperToolError(_ message: String) -> Bool {
        message.contains("unable to find utility") || message.contains("requires Xcode")
    }

    /// The newest installed Xcode that isn't a beta or release candidate.
    var latestInstalledReleaseXcode: Xcode? {
        allXcodes
            .filter { $0.installState.installed && $0.version.prereleaseIdentifiers.isEmpty }
            .max { $0.version < $1.version }
    }

    /// Makes the Xcode active, then tries removing the platform again.
    func selectXcodeAndDeleteRuntime(xcode: Xcode, runtime: DownloadableRuntime, presentErrorInSettings: Bool) {
        select(xcode: xcode)
        Task { @MainActor [weak self] in
            // select(xcode:) starts selectTask right away unless it first has to ask to install the helper;
            // in that case the user can remove the platform again once the Xcode is active.
            guard let self, let selectTask = self.selectTask else { return }
            await selectTask.value
            guard let path = xcode.installedPath?.string, self.selectedXcodePath?.hasPrefix(path) == true else { return }
            self.confirmDeleteRuntime(runtime: runtime, presentErrorInSettings: presentErrorInSettings)
        }
    }

    private func runtimeDeletionErrorMessage(_ error: Error) -> String {
        if let error = error as? XcodesKitError {
            return error.message
        }

        if let error = error as? ProcessExecutionError {
            return error.runtimeFailureMessage
        }
        return error.localizedDescription
    }
}

// MARK: - Automatic platform downloads

/// The simulator platforms to download automatically after Xcodes installs an Xcode, as chosen in Settings.
struct AutoDownloadPlatformsSelection: Equatable {
    static let defaultsKey = "autoDownloadPlatforms"
    static let choosablePlatforms: [DownloadableRuntime.Platform] = [.iOS, .watchOS, .visionOS, .tvOS]
    private static let allToken = "all"

    var isAll: Bool
    var platforms: Set<DownloadableRuntime.Platform>

    init(isAll: Bool = false, platforms: Set<DownloadableRuntime.Platform> = []) {
        self.isAll = isAll
        self.platforms = platforms
    }

    /// Parses the stored value: "all", or a comma-separated list of platform identifiers.
    init(rawValue: String) {
        let components = rawValue.split(separator: ",").map(String.init)
        self.isAll = components.contains(Self.allToken)
        self.platforms = Set(components.compactMap(DownloadableRuntime.Platform.init(rawValue:)))
    }

    var rawValue: String {
        if isAll { return Self.allToken }
        return Self.choosablePlatforms.filter(platforms.contains).map(\.rawValue).joined(separator: ",")
    }

    var isEmpty: Bool {
        !isAll && platforms.isEmpty
    }

    func includes(_ platform: DownloadableRuntime.Platform) -> Bool {
        isAll || platforms.contains(platform)
    }
}

extension AppState {
    /// Picks one runtime per selected platform that matches the Xcode's SDKs and the architecture variant,
    /// skipping platforms that are already installed or installing.
    static func runtimesToAutoDownload(
        sdkBuilds: [String],
        downloadableRuntimes: [DownloadableRuntime],
        selection: AutoDownloadPlatformsSelection,
        variant: ArchitectureVariant,
        isInstalled: (DownloadableRuntime) -> Bool
    ) -> [DownloadableRuntime] {
        guard !selection.isEmpty else { return [] }

        let candidates = downloadableRuntimes.filter { runtime in
            selection.includes(runtime.platform) &&
                sdkBuilds.contains { runtime.sdkBuildUpdate?.contains($0) ?? false } &&
                runtime.supports(variant)
        }

        var runtimesByPlatform: [DownloadableRuntime.Platform: DownloadableRuntime] = [:]
        for runtime in candidates {
            guard let existing = runtimesByPlatform[runtime.platform] else {
                runtimesByPlatform[runtime.platform] = runtime
                continue
            }
            // Prefer the newest simulator build for the platform
            if runtime.simulatorVersion.buildUpdate.localizedStandardCompare(existing.simulatorVersion.buildUpdate) == .orderedDescending {
                runtimesByPlatform[runtime.platform] = runtime
            }
        }

        return runtimesByPlatform.values
            .filter { runtime in
                if case .installing = runtime.installState { return false }
                return !isInstalled(runtime)
            }
            .sorted { Self.platformOrder($0.platform) < Self.platformOrder($1.platform) }
    }

    private static func platformOrder(_ platform: DownloadableRuntime.Platform) -> Int {
        AutoDownloadPlatformsSelection.choosablePlatforms.firstIndex(of: platform) ?? .max
    }

    /// Downloads the platforms chosen in Settings for an Xcode being installed, in parallel with each
    /// other and with the Xcode download, the same as pressing several Install buttons in the info pane.
    func autoDownloadPlatforms(for availableXcode: AvailableXcode) {
        let selection = AutoDownloadPlatformsSelection(rawValue: Current.defaults.string(forKey: AutoDownloadPlatformsSelection.defaultsKey) ?? "")
        guard !selection.isEmpty, let sdkBuilds = availableXcode.sdks?.allBuilds, !sdkBuilds.isEmpty else { return }

        let variant = Current.defaults.string(forKey: "selectedRuntimeArchitecture").flatMap(ArchitectureVariant.init(rawValue:)) ?? .defaultForMachine()
        let runtimes = Self.runtimesToAutoDownload(
            sdkBuilds: sdkBuilds,
            downloadableRuntimes: downloadableRuntimes,
            selection: selection,
            variant: variant,
            isInstalled: { self.coreSimulatorInfo(runtime: $0) != nil }
        )
        guard !runtimes.isEmpty else { return }
        Logger.appState.info("Automatically downloading platforms: \(runtimes.map(\.name).joined(separator: ", "))")

        runtimes.forEach { downloadRuntime(runtime: $0, for: availableXcode.xcodeID) }
    }
}

private extension DownloadableRuntime {
    func supports(_ variant: ArchitectureVariant) -> Bool {
        guard let architectures, !architectures.isEmpty else { return true }
        switch variant {
        case .universal:
            return architectures.isUniversal
        case .appleSilicon:
            return architectures.isAppleSilicon
        }
    }
}

// MARK: - Platforms of an Xcode

extension DownloadableRuntime.Platform {
    /// The order platforms are listed in: iOS, watchOS, visionOS, tvOS.
    var displayOrder: Int {
        switch self {
        case .iOS: return 0
        case .watchOS: return 1
        case .visionOS: return 2
        case .tvOS: return 3
        case .macOS: return 4
        }
    }
}

extension AppState {
    /// Installed simulator runtimes that match this Xcode's SDKs and no other installed Xcode's,
    /// so they can be offered for removal along with it.
    func installedRuntimesUsedOnly(by xcode: Xcode) -> [DownloadableRuntime] {
        func runtimes(matching xcode: Xcode) -> Set<String> {
            let builds = xcode.platformSDKBuilds
            return Set(downloadableRuntimes
                .filter { runtime in builds.contains { runtime.sdkBuildUpdate?.contains($0) ?? false } }
                .map(\.identifier))
        }

        let otherInstalledXcodes = allXcodes.filter { $0.id != xcode.id && $0.installState.installed }
        let usedElsewhere = otherInstalledXcodes.reduce(into: Set<String>()) { $0.formUnion(runtimes(matching: $1)) }
        let candidates = runtimes(matching: xcode).subtracting(usedElsewhere)

        return downloadableRuntimes
            .filter { candidates.contains($0.identifier) && coreSimulatorInfo(runtime: $0) != nil }
            .sorted { ($0.platform.displayOrder, $1.name) < ($1.platform.displayOrder, $0.name) }
    }


}

private extension Xcode {
    var developerDirectory: String? {
        installedPath?.url.appendingPathComponent("Contents/Developer").path
    }
}
