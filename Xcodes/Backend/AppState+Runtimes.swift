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

                self.downloadableRuntimes = runtimes
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

    func downloadRuntime(runtime: DownloadableRuntime) {
        do {
            let method = try RuntimeInstallPolicy().installMethod(
                for: runtime,
                selectedXcodeVersion: allXcodes.first(where: { $0.selected })?.version
            )

            switch method {
            case .archive:
                downloadRuntimeViaArchive(runtime: runtime)
            case let .xcodebuild(architecture):
                downloadRuntimeViaXcodeBuild(runtime: runtime, architecture: architecture)
            }
        } catch {
            presentRuntimeInstallPolicyError(error)
        }
    }

    private func presentRuntimeInstallPolicyError(_ error: Error) {
        Logger.appState.error("Trying to download a runtime we can't download: \(error.localizedDescription)")

        if let error = error as? RuntimeInstallPolicyError {
            switch error {
            case .noSelectedXcode:
                presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: "No selected Xcode. Please make an Xcode active")
            case .xcode16_1OrGreaterRequired:
                presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: localizeString("Alert.Install.Error.Need.Xcode16.1"))
            case .xcode26OrGreaterRequired:
                presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: localizeString("Alert.Install.Error.Need.Xcode26"))
            }
        } else {
            presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.legibleLocalizedDescription)
        }
    }

    func downloadRuntimeViaXcodeBuild(runtime: DownloadableRuntime, architecture: String? = nil) {
        runtimeTasks[runtime.identifier]?.cancel()
        let runtimeTaskID = UUID()
        runtimeTaskIDs[runtime.identifier] = runtimeTaskID
        runtimeTasks[runtime.identifier] = Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer {
                if self.runtimeTaskIDs[runtime.identifier] == runtimeTaskID {
                    self.runtimeTasks[runtime.identifier] = nil
                    self.runtimeTaskIDs[runtime.identifier] = nil
                }
            }
            do {
                try await RuntimeXcodebuildInstallService(download: Current.shell.downloadRuntime).downloadAndInstall(
                    runtime: runtime,
                    architecture: architecture
                ) { progress in
                    Task { @MainActor [weak self] in
                        guard
                            let self,
                            self.runtimeTaskIDs[runtime.identifier] == runtimeTaskID
                        else { return }

                        if progress.isIndeterminate {
                            self.setInstallationStep(of: runtime, to: .installing, postNotification: false)
                        } else {
                            self.setInstallationStep(of: runtime, to: .downloading(progress: progress), postNotification: false)
                        }
                    }
                }
                try Task.checkCancellation()
                Logger.appState.debug("Done downloading runtime - \(runtime.name)")

                guard let index = self.downloadableRuntimes.firstIndex(where: { $0.identifier == runtime.identifier }) else { return }
                self.downloadableRuntimes[index].installState = .installed
                self.update()

            } catch is CancellationError {
            } catch {
                Logger.appState.error("Error downloading runtime: \(error.localizedDescription)")
                self.error = error
                if let error = error as? XcodesKitError {
                    self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.message)
                } else {
                    self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.legibleLocalizedDescription)
                }
            }
        }
    }

    func downloadRuntimeViaArchive(runtime: DownloadableRuntime) {
        runtimeTasks[runtime.identifier]?.cancel()
        let runtimeTaskID = UUID()
        runtimeTaskIDs[runtime.identifier] = runtimeTaskID
        runtimeTasks[runtime.identifier] = Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer {
                if self.runtimeTaskIDs[runtime.identifier] == runtimeTaskID {
                    self.runtimeTasks[runtime.identifier] = nil
                    self.runtimeTaskIDs[runtime.identifier] = nil
                }
            }
            do {
                let downloadedURL = try await downloadRuntimeArchive(runtime: runtime, taskID: runtimeTaskID)
                try Task.checkCancellation()
                Logger.appState.debug("Installing runtime: \(runtime.name)")
                try await self.runtimeArchiveInstallService.install(
                    runtime: runtime,
                    archiveURL: downloadedURL,
                    stepChanged: { step in
                        await self.setInstallationStep(of: runtime, to: step)
                    }
                )

                guard let index = self.downloadableRuntimes.firstIndex(where: { $0.identifier == runtime.identifier }) else { return }
                self.downloadableRuntimes[index].installState = .installed
                updateInstalledRuntimes()
            } catch is CancellationError {
            } catch {
                Logger.appState.error("Error downloading runtime: \(error.localizedDescription)")
                self.error = error
                if let error = error as? XcodesKitError {
                    self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.message)
                } else {
                    self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.legibleLocalizedDescription)
                }
            }
        }
    }

    func downloadRuntimeArchive(runtime: DownloadableRuntime, taskID: UUID? = nil) async throws -> URL {
        let downloader = Downloader(rawValue: Current.defaults.string(forKey: "downloader") ?? "aria2") ?? .aria2

        Logger.appState.info("Downloading \(runtime.visibleIdentifier) with \(downloader)")
        let archiveURL = try await runtimeArchiveService().archiveURL(
            for: runtime,
            destinationDirectory: .xcodesApplicationSupport,
            downloader: downloader
        ) { progress in
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

    private var runtimeArchiveInstallService: RuntimeArchiveInstallService {
        let runtimeService = self.runtimeService
        return RuntimeArchiveInstallService(
            installDiskImage: { url in
                try await runtimeService.installRuntimeImage(dmgURL: url)
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

    func deleteRuntime(runtime: DownloadableRuntime) async throws {
        if let info = coreSimulatorInfo(runtime: runtime) {
            try await runtimeService.deleteRuntime(identifier: info.uuid)

            // give it some time to actually finish deleting before updating
            try await Task.sleep(nanoseconds: 500_000_000)
            updateInstalledRuntimes()
        } else {
            throw XcodesKitError("No simulator found with \(runtime.identifier)")
        }
    }

    /// - Parameter presentErrorInSettings: Show failures in the Settings window (Platforms list) instead of the main window.
    func confirmDeleteRuntime(runtime: DownloadableRuntime, presentErrorInSettings: Bool = true) {
        deleteRuntimeTask?.cancel()
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
                if presentErrorInSettings {
                    self.presentedPreferenceAlert = .generic(
                        title: "Error",
                        message: self.runtimeDeletionErrorMessage(error)
                    )
                } else {
                    self.presentedAlert = .generic(
                        title: "Error",
                        message: self.runtimeDeletionErrorMessage(error)
                    )
                }
            }
        }
    }

    private func runtimeDeletionErrorMessage(_ error: Error) -> String {
        if let error = error as? XcodesKitError {
            return error.message
        }

        return error.localizedDescription
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
            let builds = xcode.sdks?.allBuilds ?? []
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

    /// Uninstalls an Xcode, then removes the given simulator runtimes.
    func uninstall(xcode: Xcode, removingRuntimes runtimes: [DownloadableRuntime]) {
        uninstall(xcode: xcode)
        guard !runtimes.isEmpty else { return }
        Task { @MainActor [weak self] in
            // Remove the platforms once the Xcode itself is gone, so a failure there doesn't leave it half-removed
            await self?.uninstallTask?.value
            for runtime in runtimes {
                do {
                    try await self?.deleteRuntime(runtime: runtime)
                } catch {
                    self?.presentedAlert = .generic(title: "Error", message: error.legibleLocalizedDescription)
                }
            }
        }
    }
}
