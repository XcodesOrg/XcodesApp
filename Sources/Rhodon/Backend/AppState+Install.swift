import AppleAPI
import DockProgress
import Foundation
import os.log
import Path
import Version
import RhodonKit

/// Downloads and installs Rhodon
extension AppState {
    /// check to see if we should auto install for the user
    func autoInstallIfNeeded() {
        guard
            let storageValue = current.defaults.get(forKey: "autoInstallation") as? Int,
            let autoInstallType = AutoInstallationType(rawValue: storageValue) else { return }

        if autoInstallType == .none { return }

        guard let newestXcode = allRhodon.first, newestXcode.installState == .notInstalled else {
            Logger.appState.info("User has latest Xcode already installed")
            return
        }

        if autoInstallType == .newestBeta {
            Logger.appState.info("Auto installing newest Xcode Beta")
            checkMinVersionAndInstall(id: newestXcode.id)
        } else if autoInstallType == .newestVersion, newestXcode.version.isNotPrerelease {
            Logger.appState.info("Auto installing newest Xcode")
            checkMinVersionAndInstall(id: newestXcode.id)
        } else {
            Logger.appState.info("No new Rhodon version found to auto install")
        }
    }

    func install(_ installationType: InstallationType, downloader: Downloader) async throws {
        _ = try await install(installationType, downloader: downloader, attemptNumber: 0)
    }

    private func install(
        _ installationType: InstallationType,
        downloader: Downloader,
        attemptNumber: Int
    ) async throws -> InstalledXcode {
        Logger.appState.info("Using \(downloader) downloader")
        setupDockProgress()

        do {
            try await authenticationStore.validateSession()
            let (xcode, archiveURL) = try await getXcodeArchive(installationType, downloader: downloader)
            let installedXcode = try await installArchivedXcode(xcode, at: archiveURL)
            updateInstalledState(for: installedXcode)
            return installedXcode
        } catch {
            return try await recoverFromInstallError(
                error,
                installationType: installationType,
                downloader: downloader,
                attemptNumber: attemptNumber
            )
        }
    }

    private func recoverFromInstallError(
        _ error: Error,
        installationType: InstallationType,
        downloader: Downloader,
        attemptNumber: Int
    ) async throws -> InstalledXcode {
        resetDockProgressTracking()

        guard
            case let InstallationError.damagedXIP(damagedXIPURL) = error,
            attemptNumber < 1
        else {
            throw error
        }

        switch installationType {
        case .version:
            Logger.appState.error("\(error.legibleLocalizedDescription)")
            Logger.appState.info("Removing damaged XIP and re-attempting installation.")
            try current.files.removeItem(at: damagedXIPURL)
            return try await install(installationType, downloader: downloader, attemptNumber: attemptNumber + 1)
        }
    }

    private func updateInstalledState(for installedXcode: InstalledXcode) {
        guard
            let index = allRhodon.firstIndex(where: { $0.version.isEquivalent(to: installedXcode.version) })
        else { return }
        allRhodon[index].installState = .installed(installedXcode.path)
    }

    private func getXcodeArchive(
        _ installationType: InstallationType,
        downloader: Downloader
    ) async throws -> (AvailableXcode, URL) {
        switch installationType {
        case let .version(availableXcode):
            if
                let installedXcode = current.files.installedRhodon(Path.installDirectory)
                    .first(where: { $0.version.isEquivalent(to: availableXcode.version) }) {
                throw InstallationError.versionAlreadyInstalled(installedXcode)
            }

            let archiveURL = try await downloadXcode(availableXcode: availableXcode, downloader: downloader)
            return (availableXcode, archiveURL)
        }
    }

    private func downloadXcode(availableXcode: AvailableXcode, downloader: Downloader) async throws -> URL {
        try await downloadOrUseExistingArchive(
            for: availableXcode,
            downloader: downloader,
            progressChanged: { [unowned self] progress in
                self.setInstallationStep(of: availableXcode.version, to: .downloading(progress: progress))
                self.overallProgress.addChild(
                    progress,
                    withPendingUnitCount: AppState.totalProgressUnits - AppState.unxipProgressWeight
                )
            }
        )
    }

    func downloadOrUseExistingArchive(
        for availableXcode: AvailableXcode,
        downloader: Downloader,
        progressChanged: @escaping (Progress) -> Void
    ) async throws -> URL {
        let archiveFileExtension = availableXcode.filename.suffix(fromLast: ".")
        let archiveFilename = "Xcode-\(availableXcode.version).\(archiveFileExtension)"
        let expectedArchivePath = Path.rhodonApplicationSupport / archiveFilename
        let aria2DownloadMetadataPath = expectedArchivePath.parent / (expectedArchivePath.basename() + ".aria2")
        let aria2DownloadIsIncomplete = downloader == .aria2 && aria2DownloadMetadataPath.exists

        if current.files.fileExistsAtPath(expectedArchivePath.string), !aria2DownloadIsIncomplete {
            Logger.appState.info("Found existing archive that will be used for installation at \(expectedArchivePath).")
            return expectedArchivePath.url
        }

        let destination = Path.rhodonApplicationSupport / archiveFilename
        switch downloader {
        case .aria2:
            guard let aria2Path = current.shell.aria2Path() else {
                throw Aria2UnavailableError()
            }

            return try await downloadXcodeWithAria2(
                availableXcode,
                to: destination,
                aria2Path: aria2Path,
                progressChanged: progressChanged
            )
        case .urlSession:
            return try await downloadXcodeWithURLSession(
                availableXcode,
                to: destination,
                progressChanged: progressChanged
            )
        }
    }

    func downloadXcodeWithAria2(
        _ availableXcode: AvailableXcode,
        to destination: Path,
        aria2Path: Path,
        progressChanged: @escaping (Progress) -> Void
    ) async throws -> URL {
        let cookies = AppleAPI.current.network.session.configuration.httpCookieStorage?
            .cookies(for: availableXcode.url) ?? []

        for try await progress in current.shell.downloadWithAria2(
            aria2Path,
            availableXcode.url,
            destination,
            cookies
        ) {
            progressChanged(progress)
        }

        return destination.url
    }

    func downloadXcodeWithURLSession(
        _ availableXcode: AvailableXcode,
        to destination: Path,
        progressChanged: @escaping (Progress) -> Void
    ) async throws -> URL {
        let resumeDataPath = Path.rhodonApplicationSupport / "Xcode-\(availableXcode.version).resumedata"
        let persistedResumeData = current.files.contents(atPath: resumeDataPath.string)

        do {
            let saveLocation = try await attemptResumableTask(maximumRetryCount: 3) { resumeData in
                let (progress, task) = current.network.downloadTask(
                    with: availableXcode.url,
                    to: destination.url,
                    resumingWith: resumeData ?? persistedResumeData
                )
                progressChanged(progress)
                return try await task.value.saveLocation
            }
            persistOrCleanUpResumeData(at: resumeDataPath, for: .success(()))
            return saveLocation
        } catch {
            persistOrCleanUpResumeData(at: resumeDataPath, for: .failure(error))
            throw error
        }
    }

    func installArchivedXcode(_ availableXcode: AvailableXcode, at archiveURL: URL) async throws -> InstalledXcode {
        unxipProgress.completedUnitCount = 0
        overallProgress.addChild(unxipProgress, withPendingUnitCount: AppState.unxipProgressWeight)

        let destinationURL = Path.installDirectory
            .join("Xcode-\(availableXcode.version.descriptionWithoutBuildMetadata).app").url
        switch archiveURL.pathExtension {
        case "xip":
            let xcodeURL = try await unarchiveAndMoveXIP(
                availableXcode: availableXcode,
                at: archiveURL,
                to: destinationURL
            )
            let installedXcode = try installedXcode(at: xcodeURL)
            let verifiedXcode = try await trashArchiveAndVerifyXcode(
                installedXcode,
                availableXcode: availableXcode,
                archiveURL: archiveURL
            )
            return try await performPostInstallStepsRecoveringErrors(
                for: verifiedXcode,
                availableXcode: availableXcode
            )
        case "dmg":
            throw InstallationError.unsupportedFileFormat(extension: "dmg")
        default:
            throw InstallationError.unsupportedFileFormat(extension: archiveURL.pathExtension)
        }
    }

    private func installedXcode(at xcodeURL: URL) throws -> InstalledXcode {
        guard
            let path = Path(url: xcodeURL),
            current.files.fileExists(atPath: path.string),
            let installedXcode = InstalledXcode(path: path)
        else { throw InstallationError.failedToMoveXcodeToApplications }
        return installedXcode
    }

    private func trashArchiveAndVerifyXcode(
        _ installedXcode: InstalledXcode,
        availableXcode: AvailableXcode,
        archiveURL: URL
    ) async throws -> InstalledXcode {
        setInstallationStep(of: availableXcode.version, to: .trashingArchive)
        try current.files.trashItem(at: archiveURL)
        setInstallationStep(of: availableXcode.version, to: .checkingSecurity)

        async let securityAssessment: Void = verifySecurityAssessment(of: installedXcode)
        async let signingCertificate: Void = verifySigningCertificate(of: installedXcode.path.url)
        _ = try await (securityAssessment, signingCertificate)
        return installedXcode
    }

    private func performPostInstallStepsRecoveringErrors(
        for installedXcode: InstalledXcode,
        availableXcode: AvailableXcode
    ) async throws -> InstalledXcode {
        setInstallationStep(of: availableXcode.version, to: .finishing)

        do {
            try await performPostInstallSteps(for: installedXcode)
        } catch {
            self.error = error
            presentedAlert = .generic(
                title: "Unable to install archived Xcode",
                message: error.legibleLocalizedDescription
            )
        }
        resetDockProgressTracking()
        return installedXcode
    }
}
