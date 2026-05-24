import Foundation
@preconcurrency import Path
@preconcurrency import Version
import LegibleError
import os.log
import DockProgress
import XcodesKit
import XcodesLoginKit

/// Downloads and installs Xcodes
extension AppState {

    // check to see if we should auto install for the user
    public func autoInstallIfNeeded() {
        guard let storageValue = Current.defaults.get(forKey: "autoInstallation") as? Int, let autoInstallType = AutoInstallationType(rawValue: storageValue) else { return }

        let decision = XcodeAutoInstallService().decision(
            autoInstallationType: autoInstallType,
            xcodes: allXcodes.map(\.listItem)
        )

        switch decision {
        case .disabled:
            return
        case .alreadyInstalled:
            Logger.appState.info("User has latest Xcode already installed")
        case let .installNewestBeta(id):
            Logger.appState.info("Auto installing newest Xcode Beta")
            checkMinVersionAndInstall(id: id)
        case let .installNewestVersion(id):
            Logger.appState.info("Auto installing newest Xcode")
            checkMinVersionAndInstall(id: id)
        case .noNewVersion:
            Logger.appState.info("No new Xcodes version found to auto install")
        }
    }

    func installAsync(_ installationType: InstallationType, downloader: Downloader, attemptNumber: Int) async throws -> InstalledXcode {
        try await xcodeInstallRetryService.install(
            attemptNumber: attemptNumber,
            shouldRetryAfterDamagedArchive: installationType.shouldRetryAfterDamagedArchive,
            attempt: { @MainActor _ in
                Logger.appState.info("Using \(downloader) downloader")
                setupDockProgress()

                try await validateSessionAsync()
                let (xcode, url) = try await getXcodeArchiveAsync(installationType, downloader: downloader)
                try Task.checkCancellation()
                let installedXcode = try await installArchivedXcodeAsync(xcode, at: url)

                guard let index = allXcodes.firstIndex(where: { $0.version.isEquivalent(to: installedXcode.version) }) else {
                    return installedXcode
                }
                allXcodes[index].installState = .installed(installedXcode.path)
                return installedXcode
            },
            onAttemptFailed: { @MainActor _ in
                resetDockProgressTracking()
            },
            onRetryDamagedArchive: { error, _ in
                Logger.appState.error("\(error.legibleLocalizedDescription)")
                Logger.appState.info("Removing damaged XIP and re-attempting installation.")
            }
        )
    }

    private var xcodeInstallRetryService: XcodeInstallRetryService {
        XcodeInstallRetryService(
            damagedArchiveURL: { error in
                guard case InstallationError.damagedXIP(let url) = error else { return nil }
                return url
            },
            removeDamagedArchive: { url in
                try Current.files.removeItem(at: url)
            }
        )
    }

    private func getXcodeArchiveAsync(_ installationType: InstallationType, downloader: Downloader) async throws -> (AvailableXcode, URL) {
        switch installationType {
        case .version(let availableXcode):
            let resolution = try mapInstallResolutionError {
                try XcodeInstallResolutionService().resolve(
                    .availableXcode(availableXcode),
                    availableXcodes: [],
                    installedXcodes: Current.files.installedXcodes(Path.installDirectory),
                    willInstall: true
                )
            }

            return try await archive(for: resolution, downloader: downloader)
        }
    }

    private func archive(for resolution: XcodeInstallResolution, downloader: Downloader) async throws -> (AvailableXcode, URL) {
        switch resolution {
        case let .download(_, .some(availableXcode)):
            return try await downloadXcodeAsync(availableXcode: availableXcode, downloader: downloader)
        case .download:
            throw XcodesKitError("Expected Xcode install resolution to include a selected Xcode")
        case let .localArchive(xcode, url):
            return (xcode, url)
        }
    }

    private func mapInstallResolutionError<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as XcodeInstallResolutionError {
            switch error {
            case let .invalidVersion(version):
                throw InstallationError.invalidVersion(version)
            case .noReleaseVersionAvailable:
                throw InstallationError.noNonPrereleaseVersionAvailable
            case .noPrereleaseVersionAvailable:
                throw InstallationError.noPrereleaseVersionAvailable
            case let .versionAlreadyInstalled(installedXcode):
                throw InstallationError.versionAlreadyInstalled(installedXcode)
            }
        }
    }

    private func downloadXcodeAsync(availableXcode: AvailableXcode, downloader: Downloader) async throws -> (AvailableXcode, URL) {
        let expectedInstallationTaskID = installationTaskIDs[availableXcode.xcodeID]
        let url = try await downloadOrUseExistingArchiveAsync(for: availableXcode, downloader: downloader, progressChanged: { [unowned self] progress in
            Task { @MainActor in
                if let expectedInstallationTaskID, self.installationTaskIDs[availableXcode.xcodeID] != expectedInstallationTaskID {
                    return
                }
                self.setInstallationStep(of: availableXcode.version, to: .downloading(progress: progress))
                self.addDockProgressChildIfNeeded(progress, withPendingUnitCount: AppState.totalProgressUnits - AppState.unxipProgressWeight)
            }
        })

        return (availableXcode, url)
    }

    public func downloadOrUseExistingArchiveAsync(for availableXcode: AvailableXcode, downloader: Downloader, progressChanged: @escaping @Sendable (Progress) -> Void) async throws -> URL {
        let url = try await archiveService().archiveURL(
            for: XcodeArchive(availableXcode),
            downloader: downloader,
            progressChanged: progressChanged
        )
        Logger.appState.info("Using Xcode archive at \(url.path).")
        return url
    }

    private func archiveService() -> XcodeArchiveService {
        XcodeArchiveService(
            applicationSupportPath: Path.xcodesApplicationSupport,
            fileExists: { Current.files.fileExistsAtPath($0.string) },
            download: { archive, destination, downloader, progressChanged in
                try await self.archiveDownloadStrategyService.download(
                    archive: archive,
                    destination: destination,
                    downloader: downloader,
                    applicationSupportPath: Path.xcodesApplicationSupport,
                    progressChanged: progressChanged
                )
            }
        )
    }

    private var archiveDownloadStrategyService: ArchiveDownloadStrategyService {
        ArchiveDownloadStrategyService(
            archiveDownloadService: archiveDownloadService,
            aria2Path: { Path(url: Bundle.main.url(forAuxiliaryExecutable: "aria2c")!)! },
            cookiesForURL: { Current.network.session.configuration.httpCookieStorage?.cookies(for: $0) ?? [] }
        )
    }

    private var archiveDownloadService: ArchiveDownloadService {
        ArchiveDownloadService(
            aria2Download: { aria2Path, url, destination, cookies in
                Current.shell.downloadWithAria2Async(aria2Path, url, destination, cookies)
            },
            urlSessionDownload: { url, destination, resumeData in
                Current.network.downloadTaskAsync(with: url, to: destination, resumingWith: resumeData)
            },
            contentsAtPath: { path in
                Current.files.contents(atPath: path)
            },
            createFile: { path, data in
                Current.files.createFile(atPath: path, contents: data)
            },
            removeItem: { try Current.files.removeItem(at: $0) },
            shouldRetry: { error in
                error as? AuthenticationError != .notAuthorized
            },
            validateResponse: { response in
                try ArchiveDownloadService.validateDeveloperDownloadResponse(
                    response,
                    unauthorizedError: { AuthenticationError.notAuthorized }
                )
            }
        )
    }

    public func installArchivedXcodeAsync(_ availableXcode: AvailableXcode, at archiveURL: URL) async throws -> InstalledXcode {
        unxipProgress.completedUnitCount = 0
        addDockProgressChildIfNeeded(unxipProgress, withPendingUnitCount: AppState.unxipProgressWeight)

        let installedXcode: InstalledXcode
        do {
            installedXcode = try await xcodeArchiveInstallService.installArchivedXcode(
                availableXcode,
                at: archiveURL,
                cleanArchive: { try Current.files.trashItem(at: $0) }
            ) { step in
                switch step {
                case .unarchive(.unarchiving):
                    await self.setInstallationStep(of: availableXcode.version, to: .unarchiving)
                case let .unarchive(.moving(destination)):
                    await self.setInstallationStep(of: availableXcode.version, to: .moving(destination: destination))
                case .cleaningArchive:
                    await self.setInstallationStep(of: availableXcode.version, to: .trashingArchive)
                case .checkingSecurity:
                    await self.setInstallationStep(of: availableXcode.version, to: .checkingSecurity)
                }
            }
        } catch {
            throw mapXcodeArchiveInstallError(error, availableXcode: availableXcode)
        }

        setInstallationStep(of: availableXcode.version, to: .finishing)
        do {
            try await performPostInstallStepsAsync(for: installedXcode)
        } catch {
            self.error = error
            self.presentedAlert = .generic(title: localizeString("Alert.InstallArchive.Error.Title"), message: error.legibleLocalizedDescription)
        }
        resetDockProgressTracking()

        return installedXcode
    }

    private var xcodeUnarchiveService: XcodeUnarchiveService {
        XcodeUnarchiveService(
            unarchive: { _ = try await self.unxipOrUnxipExperimentAsync($0) },
            fileExists: { path in Current.files.fileExists(atPath: path) },
            moveItem: { source, destination in try Current.files.moveItem(at: source, to: destination) },
            removeItem: { url in try Current.files.removeItem(at: url) }
        )
    }

    private var xcodeArchiveInstallService: XcodeArchiveInstallService {
        XcodeArchiveInstallService(
            destinationDirectory: .installDirectory,
            unarchiveService: xcodeUnarchiveService,
            validationService: xcodeValidationService,
            fileExists: { path in Current.files.fileExists(atPath: path) },
            makeInstalledXcode: { path in
                InstalledXcode(
                    path: path,
                    contentsAtPath: { path in Current.files.contents(atPath: path) },
                    loadArchitectures: Current.shell.archs
                )
            }
        )
    }

    private func mapXcodeArchiveInstallError(_ error: Error, availableXcode: AvailableXcode) -> Error {
        switch error {
        case let error as XcodeArchiveInstallError:
            switch error {
            case .failedToMoveXcodeToDestination:
                return InstallationError.failedToMoveXcodeToApplications
            case let .unsupportedFileFormat(fileExtension):
                return InstallationError.unsupportedFileFormat(extension: fileExtension)
            }
        case let error as XcodeUnarchiveError:
            switch error {
            case let .damagedXIP(url):
                return InstallationError.damagedXIP(url: url)
            case let .notEnoughFreeSpaceToExpandArchive(url):
                return InstallationError.notEnoughFreeSpaceToExpandArchive(
                    archivePath: Path(url: url)!,
                    version: availableXcode.version
                )
            }
        case let error as XcodeValidationError:
            switch error {
            case let .failedSecurityAssessment(xcode, output):
                return InstallationError.failedSecurityAssessment(xcode: xcode, output: output)
            case let .codesignVerifyFailed(output):
                return InstallationError.codesignVerifyFailed(output: output)
            case let .unexpectedCodeSigningIdentity(identifier, certificateAuthority):
                return InstallationError.unexpectedCodeSigningIdentity(
                    identifier: identifier,
                    certificateAuthority: certificateAuthority
                )
            }
        default:
            return error
        }
    }

    func unxipOrUnxipExperimentAsync(_ source: URL) async throws -> ProcessOutput {
        if unxipExperiment {
            // All hard work done by https://github.com/saagarjha/unxip
            // Compiled to binary with `swiftc -parse-as-library -O unxip.swift`
            return try await Current.shell.unxipExperiment(source)
        } else {
            return try await Current.shell.unxip(source)
        }
    }

    private var xcodeValidationService: XcodeValidationService {
        XcodeValidationService(
            assessSecurity: { url in try await Current.shell.spctlAssess(url) },
            verifyCodesign: { url in try await Current.shell.codesignVerify(url) }
        )
    }

    // MARK: - Post-Install

    /// Attemps to install the helper once, then performs all post-install steps
    public func performPostInstallSteps(for xcode: InstalledXcode) {
        postInstallTask?.cancel()
        let taskID = UUID()
        postInstallTaskID = taskID
        postInstallTask = Task { @MainActor in
            defer {
                if postInstallTaskID == taskID {
                    postInstallTask = nil
                    postInstallTaskID = nil
                }
            }
            do {
                try await performPostInstallStepsAsync(for: xcode)
            } catch is CancellationError {
            } catch {
                guard postInstallTaskID == taskID else { return }
                self.error = error
                self.presentedAlert = .generic(title: localizeString("Alert.PostInstall.Title"), message: error.legibleLocalizedDescription)
            }
        }
    }

    /// Attemps to install the helper once, then performs all post-install steps
    public func performPostInstallStepsAsync(for xcode: InstalledXcode) async throws {
        do {
            if helperInstallState != .installed {
                // If the helper isn't installed yet then we need to prepare the user for the install prompt,
                // and then actually perform the installation.
                try await waitForHelperInstallConsent(version: xcode.version)
            }

            try await installHelperIfNecessaryAsync()
            try await xcodePostInstallWorkflowService.performPostInstallSteps(for: xcode)
        } catch {
            Logger.appState.error("Performing post-install steps failed: \(error.legibleLocalizedDescription)")
            throw InstallationError.postInstallStepsNotPerformed(version: xcode.version, helperInstallState: helperInstallState)
        }
    }

    private func waitForHelperInstallConsent(version: Version) async throws {
        unxipProgress.completedUnitCount = AppState.totalProgressUnits
        resetDockProgressTracking()

        let helperConsent = OneShotContinuation<Void>()
        let helperPreparationID = UUID()
        try await helperConsent.value(onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.helperActionPreparationID == helperPreparationID else { return }
                self.helperActionPreparationID = nil
                self.isPreparingUserForActionRequiringHelper = nil
                if self.presentedAlert?.id == XcodesAlert.privilegedHelper.id {
                    self.presentedAlert = nil
                }
            }
        }) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    helperConsent.resume(throwing: CancellationError())
                    return
                }

                self.prepareForHelperAction(preparationID: helperPreparationID) { [weak self] userConsented in
                    guard let self else {
                        helperConsent.resume(throwing: CancellationError())
                        return
                    }
                    if userConsented {
                        helperConsent.resume()
                    } else {
                        Logger.appState.info("User did not consent to installing helper during post-install steps.")
                        helperConsent.resume(
                            throwing: InstallationError.postInstallStepsNotPerformed(
                                version: version,
                                helperInstallState: self.helperInstallState
                            )
                        )
                    }
                }
            }
        }
    }

    private var xcodePostInstallWorkflowService: XcodePostInstallWorkflowService {
        XcodePostInstallWorkflowService(
            preparationService: xcodePostInstallPreparationService,
            postInstallService: xcodePostInstallService
        )
    }

    private var xcodePostInstallService: XcodePostInstallService {
        XcodePostInstallService(
            runFirstLaunch: { xcode in try await Current.helper.runFirstLaunchAsync(xcode.path.string) },
            getUserCacheDirectory: { try await Current.shell.getUserCacheDir() },
            getMacOSBuildVersion: { try await Current.shell.buildVersion() },
            getXcodeBuildVersion: { xcode in try await Current.shell.xcodeBuildVersion(xcode) },
            touchInstallCheck: { cacheDirectory, macOSBuildVersion, toolsVersion in
                try await Current.shell.touchInstallCheck(cacheDirectory, macOSBuildVersion, toolsVersion)
            }
        )
    }

    private var xcodePostInstallPreparationService: XcodePostInstallPreparationService {
        XcodePostInstallPreparationService(
            enableDeveloperTools: { try await Current.helper.devToolsSecurityEnableAsync() },
            addStaffToDevelopersGroup: { try await Current.helper.addStaffToDevelopersGroupAsync() },
            acceptLicense: { xcode in try await Current.helper.acceptXcodeLicenseAsync(xcode.path.string) }
        )
    }

    // MARK: - Dock Progress Tracking

    private func setupDockProgress() {
        DockProgress.progressInstance = nil
        DockProgress.style = .bar

        let progress = Progress(totalUnitCount: AppState.totalProgressUnits)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        overallProgress = progress
        overallProgressChildIDs = []
        unxipProgress = AppState.makeUnxipProgress()

        DockProgress.progressInstance = overallProgress

    }

    private func addDockProgressChildIfNeeded(_ progress: Progress, withPendingUnitCount pendingUnitCount: Int64) {
        let progressID = ObjectIdentifier(progress)
        guard overallProgressChildIDs.insert(progressID).inserted else { return }
        overallProgress.addChild(progress, withPendingUnitCount: pendingUnitCount)
    }

    func resetDockProgressTracking() {
        DockProgress.progress = 1 // Only way to completely remove overlay with DockProgress is setting progress to complete
    }

    // MARK: -

    func setInstallationStep(of version: Version, to step: XcodeInstallationStep) {
        guard let index = allXcodes.firstIndex(where: { $0.version.isEquivalent(to: version) }) else { return }
        allXcodes[index].installState = .installing(step)

        let xcode = allXcodes[index]
        Current.notificationManager.scheduleNotification(title: xcode.version.major.description + "." + xcode.version.appleDescription, body: step.description, category: .normal)
    }

    func setInstallationStep(of runtime: DownloadableRuntime, to step: RuntimeInstallationStep, postNotification: Bool = true) {
        guard let index = downloadableRuntimes.firstIndex(where: { $0.identifier == runtime.identifier }) else { return }
        downloadableRuntimes[index].installState = .installing(step)
        if postNotification {
            Current.notificationManager.scheduleNotification(title: runtime.name, body: step.description, category: .normal)
        }
    }
}

public enum InstallationError: LocalizedError, Equatable {
    case damagedXIP(url: URL)
    case notEnoughFreeSpaceToExpandArchive(archivePath: Path, version: Version)
    case failedToMoveXcodeToApplications
    case failedSecurityAssessment(xcode: InstalledXcode, output: String)
    case codesignVerifyFailed(output: String)
    case unexpectedCodeSigningIdentity(identifier: String, certificateAuthority: [String])
    case unsupportedFileFormat(extension: String)
    case missingSudoerPassword
    case unavailableVersion(Version)
    case noNonPrereleaseVersionAvailable
    case noPrereleaseVersionAvailable
    case missingUsernameOrPassword
    case versionAlreadyInstalled(InstalledXcode)
    case invalidVersion(String)
    case versionNotInstalled(Version)
    case postInstallStepsNotPerformed(version: Version, helperInstallState: HelperInstallState)

    public var errorDescription: String? {
        switch self {
        case .damagedXIP(let url):
            return String(format: localizeString("InstallationError.DamagedXIP"), url.lastPathComponent)
        case let .notEnoughFreeSpaceToExpandArchive(archivePath, version):
            return String(format: localizeString("InstallationError.NotEnoughFreeSpaceToExpandArchive"), archivePath.basename(), version.appleDescription)
        case .failedToMoveXcodeToApplications:
            return String(format: localizeString("InstallationError.FailedToMoveXcodeToApplications"), Path.installDirectory.string)
        case .failedSecurityAssessment(let xcode, let output):
            return String(format: localizeString("InstallationError.FailedSecurityAssessment"), String(xcode.version), output, xcode.path.string)
        case .codesignVerifyFailed(let output):
            return String(format: localizeString("InstallationError.CodesignVerifyFailed"), output)
        case .unexpectedCodeSigningIdentity(let identity, let certificateAuthority):
            return String(format: localizeString("InstallationError.UnexpectedCodeSigningIdentity"), identity, certificateAuthority, XcodeTeamIdentifier, XcodeCertificateAuthority)
        case .unsupportedFileFormat(let fileExtension):
            return String(format: localizeString("InstallationError.UnsupportedFileFormat"), fileExtension)
        case .missingSudoerPassword:
            return localizeString("InstallationError.MissingSudoerPassword")
        case let .unavailableVersion(version):
            return String(format: localizeString("InstallationError.UnavailableVersion"), version.appleDescription)
        case .noNonPrereleaseVersionAvailable:
            return localizeString("InstallationError.NoNonPrereleaseVersionAvailable")
        case .noPrereleaseVersionAvailable:
            return localizeString("InstallationError.NoPrereleaseVersionAvailable")
        case .missingUsernameOrPassword:
            return localizeString("InstallationError.MissingUsernameOrPassword")
        case let .versionAlreadyInstalled(installedXcode):
            return String(format: localizeString("InstallationError.VersionAlreadyInstalled"), installedXcode.version.appleDescription, installedXcode.path.string)
        case let .invalidVersion(version):
            return String(format: localizeString("InstallationError.InvalidVersion"), version)
        case let .versionNotInstalled(version):
            return String(format: localizeString("InstallationError.VersionNotInstalled"), version.appleDescription)
        case let .postInstallStepsNotPerformed(version, helperInstallState):
            switch helperInstallState {
            case .installed:
                return String(format: localizeString("InstallationError.PostInstallStepsNotPerformed.Installed"), version.appleDescription)
            case .notInstalled, .unknown:
                return String(format: localizeString("InstallationError.PostInstallStepsNotPerformed.NotInstalled"), version.appleDescription)
            }
        }
    }
}

public enum InstallationType: Sendable {
    case version(AvailableXcode)

    var shouldRetryAfterDamagedArchive: Bool {
        switch self {
        case .version:
            return true
        }
    }
}

let XcodeTeamIdentifier = XcodeSignatureVerifier.expectedTeamIdentifier
let XcodeCertificateAuthority = XcodeSignatureVerifier.expectedCertificateAuthority
