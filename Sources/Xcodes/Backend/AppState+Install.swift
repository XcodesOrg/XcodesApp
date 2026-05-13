import AppleAPI
import Combine
import DockProgress
import Foundation
import os.log
import Path
import Version
import XcodesKit

final class PassthroughSubjectBox<Output, Failure: Error>: @unchecked Sendable {
    private let subject = PassthroughSubject<Output, Failure>()

    func send(_ value: Output) {
        subject.send(value)
    }

    func send(completion: Subscribers.Completion<Failure>) {
        subject.send(completion: completion)
    }

    var publisher: AnyPublisher<Output, Failure> {
        subject.eraseToAnyPublisher()
    }
}

/// Downloads and installs Xcodes
extension AppState {
    /// check to see if we should auto install for the user
    func autoInstallIfNeeded() {
        guard
            let storageValue = current.defaults.get(forKey: "autoInstallation") as? Int,
            let autoInstallType = AutoInstallationType(rawValue: storageValue) else { return }

        if autoInstallType == .none { return }

        // get newest xcode version
        guard let newestXcode = allXcodes.first, newestXcode.installState == .notInstalled else {
            Logger.appState.info("User has latest Xcode already installed")
            return
        }

        if autoInstallType == .newestBeta {
            Logger.appState.info("Auto installing newest Xcode Beta")
            // install it, as user doesn't have it installed and it's either latest beta or latest release
            checkMinVersionAndInstall(id: newestXcode.id)
        } else if autoInstallType == .newestVersion, newestXcode.version.isNotPrerelease {
            Logger.appState.info("Auto installing newest Xcode")
            checkMinVersionAndInstall(id: newestXcode.id)
        } else {
            Logger.appState.info("No new Xcodes version found to auto install")
        }
    }

    func install(_ installationType: InstallationType, downloader: Downloader) -> AnyPublisher<Void, Error> {
        install(installationType, downloader: downloader, attemptNumber: 0)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    private func install(
        _ installationType: InstallationType,
        downloader: Downloader,
        attemptNumber: Int
    ) -> AnyPublisher<InstalledXcode, Error> {
        Logger.appState.info("Using \(downloader) downloader")

        setupDockProgress()

        return validatedSessionPublisher()
        .flatMap { _ in
            self.getXcodeArchive(installationType, downloader: downloader)
        }
        .flatMap { xcode, url -> AnyPublisher<InstalledXcode, Swift.Error> in
            self.installArchivedXcode(xcode, at: url)
        }
        .catch { error -> AnyPublisher<InstalledXcode, Swift.Error> in
            self.recoverFromInstallError(
                error,
                installationType: installationType,
                downloader: downloader,
                attemptNumber: attemptNumber
            )
        }
        .handleEvents(receiveOutput: { installedXcode in
            self.updateInstalledState(for: installedXcode)
        })
        .eraseToAnyPublisher()
    }

    private func validatedSessionPublisher() -> AnyPublisher<Void, Error> {
        Future<Void, Error> { promise in
            nonisolated(unsafe) let promise = promise
            Task { @MainActor in
                do {
                    try await self.authenticationStore.validateSession()
                    promise(.success(()))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    private func recoverFromInstallError(
        _ error: Error,
        installationType: InstallationType,
        downloader: Downloader,
        attemptNumber: Int
    ) -> AnyPublisher<InstalledXcode, Swift.Error> {
        resetDockProgressTracking()

        guard
            case let InstallationError.damagedXIP(damagedXIPURL) = error,
            attemptNumber < 1
        else {
            return Fail(error: error).eraseToAnyPublisher()
        }

        switch installationType {
        case .version:
            do {
                Logger.appState.error("\(error.legibleLocalizedDescription)")
                Logger.appState.info("Removing damaged XIP and re-attempting installation.")
                try current.files.removeItem(at: damagedXIPURL)
                return install(installationType, downloader: downloader, attemptNumber: attemptNumber + 1)
                    .eraseToAnyPublisher()
            } catch {
                return Fail(error: error).eraseToAnyPublisher()
            }
        }
    }

    private func updateInstalledState(for installedXcode: InstalledXcode) {
        DispatchQueue.main.async {
            guard
                let index = self.allXcodes
                    .firstIndex(where: { $0.version.isEquivalent(to: installedXcode.version) }) else { return }
            self.allXcodes[index].installState = .installed(installedXcode.path)
        }
    }

    private func getXcodeArchive(_ installationType: InstallationType, downloader: Downloader) -> AnyPublisher<(
        AvailableXcode,
        URL
    ), Error> {
        switch installationType {
        case let .version(availableXcode):
            if
                let installedXcode = current.files.installedXcodes(Path.installDirectory)
                    .first(where: { $0.version.isEquivalent(to: availableXcode.version) }) {
                return Fail(error: InstallationError.versionAlreadyInstalled(installedXcode))
                    .eraseToAnyPublisher()
            }

            return downloadXcode(availableXcode: availableXcode, downloader: downloader)
        }
    }

    private func downloadXcode(availableXcode: AvailableXcode, downloader: Downloader) -> AnyPublisher<(
        AvailableXcode,
        URL
    ), Error> {
        downloadOrUseExistingArchive(
            for: availableXcode,
            downloader: downloader,
            progressChanged: { [unowned self] progress in
                DispatchQueue.main.async {
                    self.setInstallationStep(of: availableXcode.version, to: .downloading(progress: progress))
                    self.overallProgress.addChild(
                        progress,
                        withPendingUnitCount: AppState.totalProgressUnits - AppState.unxipProgressWeight
                    )
                }
            }
        )
        .map { (availableXcode, $0) }
        .eraseToAnyPublisher()
    }

    func downloadOrUseExistingArchive(
        for availableXcode: AvailableXcode,
        downloader: Downloader,
        progressChanged: @escaping (Progress) -> Void
    ) -> AnyPublisher<URL, Error> {
        // Check to see if the archive is in the expected path in case it was downloaded but failed to install
        let archiveFileExtension = availableXcode.filename.suffix(fromLast: ".")
        let archiveFilename = "Xcode-\(availableXcode.version).\(archiveFileExtension)"
        let expectedArchivePath = Path.xcodesApplicationSupport / archiveFilename
        // aria2 downloads directly to the destination (instead of into /tmp first) so we need to make sure that the
        // download isn't incomplete
        let aria2DownloadMetadataPath = expectedArchivePath.parent / (expectedArchivePath.basename() + ".aria2")
        var aria2DownloadIsIncomplete = false
        if case .aria2 = downloader, aria2DownloadMetadataPath.exists {
            aria2DownloadIsIncomplete = true
        }
        if current.files.fileExistsAtPath(expectedArchivePath.string), aria2DownloadIsIncomplete == false {
            Logger.appState.info("Found existing archive that will be used for installation at \(expectedArchivePath).")
            return Just(expectedArchivePath.url)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        } else {
            let destination = Path.xcodesApplicationSupport / archiveFilename
            switch downloader {
            case .aria2:
                guard let aria2Path = current.shell.aria2Path() else {
                    return Fail(error: Aria2UnavailableError()).eraseToAnyPublisher()
                }

                return downloadXcodeWithAria2(
                    availableXcode,
                    to: destination,
                    aria2Path: aria2Path,
                    progressChanged: progressChanged
                )
            case .urlSession:
                return downloadXcodeWithURLSession(
                    availableXcode,
                    to: destination,
                    progressChanged: progressChanged
                )
            }
        }
    }

    func downloadXcodeWithAria2(
        _ availableXcode: AvailableXcode,
        to destination: Path,
        aria2Path: Path,
        progressChanged: @escaping (Progress) -> Void
    ) -> AnyPublisher<URL, Error> {
        let cookies = AppleAPI.current.network.session.configuration.httpCookieStorage?
            .cookies(for: availableXcode.url) ?? []

        let (progress, publisher) = current.shell.downloadWithAria2(
            aria2Path,
            availableXcode.url,
            destination,
            cookies
        )
        progressChanged(progress)

        return publisher
            .map { _ in destination.url }
            .eraseToAnyPublisher()
    }

    func downloadXcodeWithURLSession(
        _ availableXcode: AvailableXcode,
        to destination: Path,
        progressChanged: @escaping (Progress) -> Void
    ) -> AnyPublisher<URL, Error> {
        let resumeDataPath = Path.xcodesApplicationSupport / "Xcode-\(availableXcode.version).resumedata"
        let persistedResumeData = current.files.contents(atPath: resumeDataPath.string)

        return attemptResumableTask(maximumRetryCount: 3) { resumeData -> AnyPublisher<URL, Error> in
            let (progress, publisher) = current.network.downloadTask(
                with: availableXcode.url,
                to: destination.url,
                resumingWith: resumeData ?? persistedResumeData
            )
            progressChanged(progress)

            return publisher
                .map(\.saveLocation)
                .eraseToAnyPublisher()
        }
        .handleEvents(receiveCompletion: { completion in
            self.persistOrCleanUpResumeData(at: resumeDataPath, for: completion)
        })
        .eraseToAnyPublisher()
    }

    func installArchivedXcode(
        _ availableXcode: AvailableXcode,
        at archiveURL: URL
    ) -> AnyPublisher<InstalledXcode, Error> {
        unxipProgress.completedUnitCount = 0
        overallProgress.addChild(unxipProgress, withPendingUnitCount: AppState.unxipProgressWeight)

        do {
            let destinationURL = Path.installDirectory
                .join("Xcode-\(availableXcode.version.descriptionWithoutBuildMetadata).app").url
            switch archiveURL.pathExtension {
            case "xip":
                return unarchiveAndMoveXIP(availableXcode: availableXcode, at: archiveURL, to: destinationURL)
                    .tryMap(installedXcode(at:))
                    .flatMap { installedXcode -> AnyPublisher<InstalledXcode, Error> in
                        self.trashArchiveAndVerifyXcode(
                            installedXcode,
                            availableXcode: availableXcode,
                            archiveURL: archiveURL
                        )
                    }
                    .flatMap { installedXcode -> AnyPublisher<InstalledXcode, Error> in
                        self.performPostInstallStepsRecoveringErrors(
                            for: installedXcode,
                            availableXcode: availableXcode
                        )
                    }
                    .eraseToAnyPublisher()
            case "dmg":
                throw InstallationError.unsupportedFileFormat(extension: "dmg")
            default:
                throw InstallationError.unsupportedFileFormat(extension: archiveURL.pathExtension)
            }
        } catch {
            return Fail(error: error)
                .eraseToAnyPublisher()
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
    ) -> AnyPublisher<InstalledXcode, Error> {
        do {
            setInstallationStep(of: availableXcode.version, to: .trashingArchive)
            try current.files.trashItem(at: archiveURL)
            setInstallationStep(of: availableXcode.version, to: .checkingSecurity)

            return verifySecurityAssessment(of: installedXcode)
                .combineLatest(verifySigningCertificate(of: installedXcode.path.url))
                .map { _ in installedXcode }
                .eraseToAnyPublisher()
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    private func performPostInstallStepsRecoveringErrors(
        for installedXcode: InstalledXcode,
        availableXcode: AvailableXcode
    ) -> AnyPublisher<InstalledXcode, Error> {
        setInstallationStep(of: availableXcode.version, to: .finishing)

        return performPostInstallSteps(for: installedXcode)
            .map { installedXcode }
            // Show post-install errors but don't fail because of them
            .handleEvents(receiveCompletion: { [unowned self] completion in
                if case let .failure(error) = completion {
                    self.error = error
                    presentedAlert = .generic(
                        title: "Unable to install archived Xcode",
                        message: error.legibleLocalizedDescription
                    )
                }
                resetDockProgressTracking()
            })
            .catch { _ in
                Just(installedXcode)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

}
