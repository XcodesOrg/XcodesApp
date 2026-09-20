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

    /// Starts installing a runtime.
    ///
    /// - Parameter presentingErrors: Whether a runtime that can't be installed right now should
    ///   raise an alert. Automatic installs only log, so that they never interrupt the user.
    func downloadRuntime(runtime: DownloadableRuntime, presentingErrors: Bool = true) {
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
            if presentingErrors {
                presentRuntimeInstallPolicyError(error)
            } else {
                Logger.appState.error("Skipping automatic install of \(runtime.visibleIdentifier): \(error.localizedDescription)")
            }
        }
    }

    /// Installs the newest runtime for each platform the user asked to keep up to date.
    ///
    /// Runs after an Xcode install finishes so the simulators a developer always needs are
    /// ready as soon as the Xcode they were installed alongside is.
    func autoInstallRuntimesIfNeeded() async {
        guard
            let rawValue = Current.defaults.string(forKey: PreferenceKey.autoInstallRuntimePlatforms.rawValue),
            let preference = AutoInstallRuntimePlatforms(rawValue: rawValue),
            !preference.platforms.isEmpty
        else { return }

        // The runtime lists are populated lazily, and an install that just finished can have
        // made an installed runtime stale, so make sure both are current before deciding.
        if downloadableRuntimes.isEmpty {
            updateDownloadableRuntimes()
            await downloadableRuntimesTask?.value
        }
        updateInstalledRuntimes()
        await installedRuntimesTask?.value

        let runtimes = RuntimeAutoInstallService().runtimesToInstall(
            platforms: preference.platforms,
            downloadableRuntimes: downloadableRuntimes,
            installedRuntimes: installedRuntimes,
            includingPrereleases: isAutoInstallingXcodeBetas
        )

        guard !runtimes.isEmpty else {
            Logger.appState.info("Every platform selected for automatic installation is already up to date")
            return
        }

        for runtime in runtimes where runtimeTasks[runtime.identifier] == nil {
            Logger.appState.info("Automatically installing runtime \(runtime.visibleIdentifier)")
            downloadRuntime(runtime: runtime, presentingErrors: false)
        }
    }

    /// Beta runtimes are only installed automatically for users who already opted into Xcode betas.
    private var isAutoInstallingXcodeBetas: Bool {
        guard let storageValue = Current.defaults.get(forKey: PreferenceKey.autoInstallation.rawValue) as? Int else { return false }
        return AutoInstallationType(rawValue: storageValue) == .newestBeta
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

    func confirmDeleteRuntime(runtime: DownloadableRuntime) {
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
                self.presentedPreferenceAlert = .generic(
                    title: "Error",
                    message: self.runtimeDeletionErrorMessage(error)
                )
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
