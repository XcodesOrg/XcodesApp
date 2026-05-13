import AppleAPI
import Foundation
import Path
import XcodesKit

extension AppState {
    func installHelperIfNecessary(shouldPrepareUserForHelperInstallation: Bool = true) {
        guard helperInstallState == .installed || shouldPrepareUserForHelperInstallation == false else {
            isPreparingUserForActionRequiringHelper = { [unowned self] userConsented in
                guard userConsented else { return }
                installHelperIfNecessary(shouldPrepareUserForHelperInstallation: false)
            }
            presentedAlert = .privilegedHelper
            return
        }

        Task {
            do {
                try await installHelperIfNecessary()
            } catch {
                self.error = error
                presentedAlert = .generic(
                    title: "Unable to install helper",
                    message: error.legibleLocalizedDescription
                )
            }
        }
    }

    func installHelperIfNecessary() async throws {
        if helperInstallState == .notInstalled {
            try await current.helper.install()
            await checkIfHelperIsInstalled()
        }
    }

    func checkIfHelperIsInstalled() async {
        helperInstallState = .unknown
        let installed = await current.helper.checkIfLatestHelperIsInstalled()
        helperInstallState = installed ? .installed : .notInstalled
    }

    func checkMinVersionAndInstall(id: XcodeID) {
        guard let availableXcode = availableXcodes.first(where: { $0.xcodeID == id }) else { return }

        if let requiredMacOSVersion = availableXcode.requiredMacOSVersion {
            if hasMinSupportedOS(requiredMacOSVersion: requiredMacOSVersion) {
                presentedAlert = .checkMinSupportedVersion(
                    xcode: availableXcode,
                    macOS: ProcessInfo.processInfo.operatingSystemVersion.versionString()
                )
                return
            }
        }

        install(id: id)
    }

    func hasMinSupportedOS(requiredMacOSVersion: String) -> Bool {
        let split = requiredMacOSVersion.components(separatedBy: ".").compactMap { Int($0) }
        let xcodeMinimumMacOSVersion = OperatingSystemVersion(
            majorVersion: split[safe: 0] ?? 0,
            minorVersion: split[safe: 1] ?? 0,
            patchVersion: split[safe: 2] ?? 0
        )

        return !ProcessInfo.processInfo.isOperatingSystemAtLeast(xcodeMinimumMacOSVersion)
    }

    func install(id: XcodeID) {
        guard let availableXcode = availableXcodes.first(where: { $0.xcodeID == id }) else { return }

        installationTasks[id] = Task {
            do {
                setInstallationStep(of: availableXcode.version, to: .authenticating)
                try await authenticationStore.signInIfNeeded()
                try await validateDownloadSession()
                try await install(
                    .version(availableXcode),
                    downloader: Downloader(rawValue: current.defaults.string(forKey: "downloader") ?? "aria2") ?? .aria2
                )
                installationTasks[id] = nil
            } catch {
                handleInstallFailure(error, id: id)
                installationTasks[id] = nil
            }
        }
    }

    private func validateDownloadSession() async throws {
        let data = try await current.network.data(for: URLRequest.downloads).0
        let decoder = configure(JSONDecoder()) {
            $0.dateDecodingStrategy = .formatted(.downloadsDateModified)
        }
        let downloads = try decoder.decode(Downloads.self, from: data)
        if downloads.hasError {
            throw AuthenticationError.invalidResult(resultString: downloads.resultsString)
        }
        if downloads.downloads == nil {
            throw AuthenticationError.invalidResult(resultString: "No download information found")
        }
    }

    private func handleInstallFailure(_ error: Error, id: XcodeID) {
        if let error = error as? AuthenticationError, case .notAuthorized = error {
            self.error = error
            presentedAlert = .unauthenticated
        } else if error as? AuthenticationError != .invalidSession {
            self.error = error
            presentedAlert = .generic(title: "Unable to install Xcode", message: error.legibleLocalizedDescription)
        }
        if let index = allXcodes.firstIndex(where: { $0.id == id }) {
            allXcodes[index].installState = .notInstalled
        }
    }

    func installWithoutLogin(id: Xcode.ID) {
        guard let availableXcode = availableXcodes.first(where: { $0.xcodeID == id }) else { return }

        installationTasks[id] = Task {
            do {
                try await install(
                    .version(availableXcode),
                    downloader: Downloader(rawValue: current.defaults.string(forKey: "downloader") ?? "aria2") ?? .aria2
                )
            } catch {
                if error as? AuthenticationError != .invalidSession {
                    self.error = error
                    presentedAlert = .generic(
                        title: "Unable to install Xcode",
                        message: error.legibleLocalizedDescription
                    )
                }
                if let index = allXcodes.firstIndex(where: { $0.id == id }) {
                    allXcodes[index].installState = .notInstalled
                }
            }
            installationTasks[id] = nil
        }
    }

    func cancelInstall(id: Xcode.ID) {
        guard let availableXcode = availableXcodes.first(where: { $0.xcodeID == id }) else { return }

        installationTasks[id]?.cancel()
        installationTasks[id] = nil

        resetDockProgressTracking()

        let archiveFileExtension = availableXcode.filename.suffix(fromLast: ".")
        let archiveFilename = "Xcode-\(availableXcode.version).\(archiveFileExtension)"
        let expectedArchivePath = Path.xcodesApplicationSupport / archiveFilename
        let aria2DownloadMetadataPath = expectedArchivePath.parent / (expectedArchivePath.basename() + ".aria2")
        try? current.files.removeItem(at: expectedArchivePath.url)
        try? current.files.removeItem(at: aria2DownloadMetadataPath.url)

        if let index = allXcodes.firstIndex(where: { $0.id == id }) {
            allXcodes[index].installState = .notInstalled
        }
    }
}
