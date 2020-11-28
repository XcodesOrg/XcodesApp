import Foundation
import PromiseKit
import Path
import AppleAPI
import Version
import LegibleError

/// Downloads and installs Xcodes
public final class XcodeInstaller {
    static let XcodeTeamIdentifier = "59GAB85EFG"
    static let XcodeCertificateAuthority = ["Software Signing", "Apple Code Signing Certification Authority", "Apple Root CA"]

    public enum Error: LocalizedError, Equatable {
        case damagedXIP(url: URL)
        case failedToMoveXcodeToDestination(Path)
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

        public var errorDescription: String? {
            switch self {
            case .damagedXIP(let url):
                return "The archive \"\(url.lastPathComponent)\" is damaged and can't be expanded."
            case .failedToMoveXcodeToDestination(let destination):
                return "Failed to move Xcode to the \(destination.string) directory."
            case .failedSecurityAssessment(let xcode, let output):
                return """
                       Xcode \(xcode.version) failed its security assessment with the following output:
                       \(output)
                       It remains installed at \(xcode.path) if you wish to use it anyways.
                       """
            case .codesignVerifyFailed(let output):
                return """
                       The downloaded Xcode failed code signing verification with the following output:
                       \(output)
                       """
            case .unexpectedCodeSigningIdentity(let identity, let certificateAuthority):
                return """
                       The downloaded Xcode doesn't have the expected code signing identity.
                       Got:
                         \(identity)
                         \(certificateAuthority)
                       Expected:
                         \(XcodeInstaller.XcodeTeamIdentifier)
                         \(XcodeInstaller.XcodeCertificateAuthority)
                       """
            case .unsupportedFileFormat(let fileExtension):
                return "xcodes doesn't (yet) support installing Xcode from the \(fileExtension) file format."
            case .missingSudoerPassword:
                return "Missing password. Please try again."
            case let .unavailableVersion(version):
                return "Could not find version \(version.xcodeDescription)."
            case .noNonPrereleaseVersionAvailable:
                return "No non-prerelease versions available."
            case .noPrereleaseVersionAvailable:
                return "No prerelease versions available."
            case .missingUsernameOrPassword:
                return "Missing username or a password. Please try again."
            case let .versionAlreadyInstalled(installedXcode):
                return "\(installedXcode.version.xcodeDescription) is already installed at \(installedXcode.path)"
            case let .invalidVersion(version):
                return "\(version) is not a valid version number."
            case let .versionNotInstalled(version):
                return "\(version.xcodeDescription) is not installed."
            }
        }
    }

    /// A numbered step
    enum InstallationStep: CustomStringConvertible {
        case downloading(version: String, progress: String)
        case unarchiving
        case moving(destination: String)
        case trashingArchive(archiveName: String)
        case checkingSecurity
        case finishing

        var description: String {
            "(\(stepNumber)/\(stepCount)) \(message)"
        }

        var message: String {
            switch self {
            case .downloading(let version, let progress):
                return "Downloading Xcode \(version): \(progress)"
            case .unarchiving:
                return "Unarchiving Xcode (This can take a while)"
            case .moving(let destination):
                return "Moving Xcode to \(destination)"
            case .trashingArchive(let archiveName):
                return "Moving Xcode archive \(archiveName) to the Trash"
            case .checkingSecurity:
                return "Checking security assessment and code signing"
            case .finishing:
                return "Finishing installation"
            }
        }

        var stepNumber: Int {
            switch self {
            case .downloading:      return 1
            case .unarchiving:      return 2
            case .moving:           return 3
            case .trashingArchive:  return 4
            case .checkingSecurity: return 5
            case .finishing:        return 6
            }
        }

        var stepCount: Int { 6 }
    }

    private var configuration: Configuration
    private var xcodeList: XcodeList

    public init(configuration: Configuration, xcodeList: XcodeList) {
        self.configuration = configuration
        self.xcodeList = xcodeList
    }
    
    public enum InstallationType {
        case version(String)
        case url(String, Path)
        case latest
        case latestPrerelease
    }
    
    public enum Downloader {
        case urlSession
        case aria2(Path)
    }

    public func install(_ installationType: InstallationType, downloader: Downloader, destination: Path) -> Promise<Void> {
        return firstly { () -> Promise<InstalledXcode> in
            return self.install(installationType, downloader: downloader, destination: destination, attemptNumber: 0)
        }
        .done { xcode in
            Current.logging.log("\nXcode \(xcode.version.descriptionWithoutBuildMetadata) has been installed to \(xcode.path.string)")
            Current.shell.exit(0)
        }
    }
    
    private func install(_ installationType: InstallationType, downloader: Downloader, destination: Path, attemptNumber: Int) -> Promise<InstalledXcode> {
        return firstly { () -> Promise<(Xcode, URL)> in
            return self.getXcodeArchive(installationType, downloader: downloader, destination: destination)
        }
        .then { xcode, url -> Promise<InstalledXcode> in
            return self.installArchivedXcode(xcode, at: url, to: destination)
        }
        .recover { error -> Promise<InstalledXcode> in
            switch error {
            case XcodeInstaller.Error.damagedXIP(let damagedXIPURL):
                guard attemptNumber < 1 else { throw error }

                switch installationType {
                case .url:
                    // If the user provided the URL, don't try to recover and leave it up to them.
                    throw error
                default:
                    // If the XIP was just downloaded, remove it and try to recover.
                    return firstly { () -> Promise<InstalledXcode> in
                        Current.logging.log(error.legibleLocalizedDescription)
                        Current.logging.log("Removing damaged XIP and re-attempting installation.\n")
                        try Current.files.removeItem(at: damagedXIPURL)
                        return self.install(installationType, downloader: downloader, destination: destination, attemptNumber: attemptNumber + 1)
                    }
                }
            default:
                throw error
            }
        }
    }
    
    private func getXcodeArchive(_ installationType: InstallationType, downloader: Downloader, destination: Path) -> Promise<(Xcode, URL)> {
        return firstly { () -> Promise<(Xcode, URL)> in
            switch installationType {
            case .latest:
                Current.logging.log("Updating...")
                
                return update()
                    .then { availableXcodes -> Promise<(Xcode, URL)> in
                        guard let latestNonPrereleaseXcode = availableXcodes.filter(\.version.isNotPrerelease).sorted(\.version).last else {
                            throw Error.noNonPrereleaseVersionAvailable
                        }
                        Current.logging.log("Latest non-prerelease version available is \(latestNonPrereleaseXcode.version.xcodeDescription)")
                        
                        if let installedXcode = Current.files.installedXcodes(destination).first(where: { $0.version.isEqualWithoutBuildMetadataIdentifiers(to: latestNonPrereleaseXcode.version) }) {
                            throw Error.versionAlreadyInstalled(installedXcode)
                        }

                        return self.downloadXcode(version: latestNonPrereleaseXcode.version, downloader: downloader)
                    }
            case .latestPrerelease:
                Current.logging.log("Updating...")
                
                return update()
                    .then { availableXcodes -> Promise<(Xcode, URL)> in
                        guard let latestPrereleaseXcode = availableXcodes
                            .filter({ $0.version.isPrerelease })
                            .filter({ $0.releaseDate != nil })
                            .sorted(by: { $0.releaseDate! < $1.releaseDate! })
                            .last
                        else {
                            throw Error.noNonPrereleaseVersionAvailable
                        }
                        Current.logging.log("Latest prerelease version available is \(latestPrereleaseXcode.version.xcodeDescription)")
                        
                        if let installedXcode = Current.files.installedXcodes(destination).first(where: { $0.version.isEqualWithoutBuildMetadataIdentifiers(to: latestPrereleaseXcode.version) }) {
                            throw Error.versionAlreadyInstalled(installedXcode)
                        }
                        
                        return self.downloadXcode(version: latestPrereleaseXcode.version, downloader: downloader)
                    }
            case .url(let versionString, let path):
                guard let version = Version(xcodeVersion: versionString) ?? versionFromXcodeVersionFile() else {
                    throw Error.invalidVersion(versionString)
                }
                let xcode = Xcode(version: version, url: path.url, filename: String(path.string.suffix(fromLast: "/")), releaseDate: nil)
                return Promise.value((xcode, path.url))
            case .version(let versionString):
                guard let version = Version(xcodeVersion: versionString) ?? versionFromXcodeVersionFile() else {
                    throw Error.invalidVersion(versionString)
                }
                if let installedXcode = Current.files.installedXcodes(destination).first(where: { $0.version.isEqualWithoutBuildMetadataIdentifiers(to: version) }) {
                    throw Error.versionAlreadyInstalled(installedXcode)
                }
                return self.downloadXcode(version: version, downloader: downloader)
            }
        }
    }

    private func versionFromXcodeVersionFile() -> Version? {
        let xcodeVersionFilePath = Path.cwd.join(".xcode-version")
        let version = (try? Data(contentsOf: xcodeVersionFilePath.url))
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(Version.init(gemVersion:))
        return version
    }

    private func downloadXcode(version: Version, downloader: Downloader) -> Promise<(Xcode, URL)> {
        return firstly { () -> Promise<Version> in
//            loginIfNeeded().map { version }
//        }
//        .then { version -> Promise<Version> in
            if self.xcodeList.shouldUpdate {
                return self.xcodeList.update().map { _ in version }
            }
            else {
                return Promise.value(version)
            }
        }
        .then { version -> Promise<(Xcode, URL)> in
            guard let xcode = self.xcodeList.availableXcodes.first(where: { version.isEqualWithoutBuildMetadataIdentifiers(to: $0.version) }) else {
                throw Error.unavailableVersion(version)
            }

            // Move to the next line
            Current.logging.log("")
            let formatter = NumberFormatter(numberStyle: .percent)
            var observation: NSKeyValueObservation?

            let promise = self.downloadOrUseExistingArchive(for: xcode, downloader: downloader, progressChanged: { progress in
                observation?.invalidate()
                observation = progress.observe(\.fractionCompleted) { progress, _ in
                    // These escape codes move up a line and then clear to the end
                    Current.logging.log("\u{1B}[1A\u{1B}[K\(InstallationStep.downloading(version: xcode.version.description, progress: formatter.string(from: progress.fractionCompleted)!))")
                }
            })

            return promise
                .get { _ in observation?.invalidate() }
                .map { return (xcode, $0) }
        }
    }

//    func loginIfNeeded(withUsername existingUsername: String? = nil) -> Promise<Void> {
//        return firstly { () -> Promise<Void> in
//            return Current.network.validateSession()
//        }
//        .recover { error -> Promise<Void> in
//            guard
//                let username = existingUsername ?? self.findUsername() ?? Current.shell.readLine(prompt: "Apple ID: "),
//                let password = self.findPassword(withUsername: username) ?? Current.shell.readSecureLine(prompt: "Apple ID Password: ")
//            else { throw Error.missingUsernameOrPassword }
//
//            return firstly { () -> Promise<Void> in
//                self.login(username, password: password)
//            }
//            .recover { error -> Promise<Void> in
//                Current.logging.log(error.legibleLocalizedDescription)
//
//                if case Client.AuthenticationErrro.invalidUsernameOrPassword = error {
//                    Current.logging.log("Try entering your password again")
//                    return self.loginIfNeeded(withUsername: username)
//                }
//                else {
//                    return Promise(error: error)
//                }
//            }
//        }
//    }
//
//    public func login(_ username: String, password: String) -> Promise<Void> {
//        return firstly { () -> Promise<Void> in
//            Current.network.login(accountName: username, password: password)
//        }
//        .recover { error -> Promise<Void> in
//
//            if let error = error as? Client.AuthenticationErrro {
//              switch error  {
//              case .invalidUsernameOrPassword(_):
//                  // remove any keychain password if we fail to log with an invalid username or password so it doesn't try again.
//                  try? Current.keychain.remove(username)
//              default:
//                  break
//              }
//            }
//
//            return Promise(error: error)
//        }
//        .done { _ in
//            try? Current.keychain.set(password, key: username)
//
//            if self.configuration.defaultUsername != username {
//                self.configuration.defaultUsername = username
//                try? self.configuration.save()
//            }
//        }
//    }

    let xcodesUsername = "XCODES_USERNAME"
    let xcodesPassword = "XCODES_PASSWORD"

    func findUsername() -> String? {
        if let username = Current.shell.env(xcodesUsername) {
            return username
        }
        else if let username = configuration.defaultUsername {
            return username
        }
        return nil
    }

    func findPassword(withUsername username: String) -> String? {
        if let password = Current.shell.env(xcodesPassword) {
            return password
        }
        else if let password = try? Current.keychain.getString(username){
            return password
        }
        return nil
    }

    public func downloadOrUseExistingArchive(for xcode: Xcode, downloader: Downloader, progressChanged: @escaping (Progress) -> Void) -> Promise<URL> {
        // Check to see if the archive is in the expected path in case it was downloaded but failed to install
        let expectedArchivePath = Path.xcodesApplicationSupport/"Xcode-\(xcode.version).\(xcode.filename.suffix(fromLast: "."))"
        // aria2 downloads directly to the destination (instead of into /tmp first) so we need to make sure that the download isn't incomplete
        let aria2DownloadMetadataPath = expectedArchivePath.parent/(expectedArchivePath.basename() + ".aria2")
        var aria2DownloadIsIncomplete = false
        if case .aria2 = downloader, aria2DownloadMetadataPath.exists {
            aria2DownloadIsIncomplete = true
        }
        if Current.files.fileExistsAtPath(expectedArchivePath.string), aria2DownloadIsIncomplete == false {
            Current.logging.log("(1/6) Found existing archive that will be used for installation at \(expectedArchivePath).")
            return Promise.value(expectedArchivePath.url)
        }
        else {
            let destination = Path.xcodesApplicationSupport/"Xcode-\(xcode.version).\(xcode.filename.suffix(fromLast: "."))"
            switch downloader {
            case .aria2(let aria2Path):
                return downloadXcodeWithAria2(
                    xcode,
                    to: destination,
                    aria2Path: aria2Path,
                    progressChanged: progressChanged
                )
            case .urlSession:
                return downloadXcodeWithURLSession(
                    xcode,
                    to: destination,
                    progressChanged: progressChanged
                )
            }
        }
    }
    
    public func downloadXcodeWithAria2(_ xcode: Xcode, to destination: Path, aria2Path: Path, progressChanged: @escaping (Progress) -> Void) -> Promise<URL> {
        let cookies = AppleAPI.Current.network.session.configuration.httpCookieStorage?.cookies(for: xcode.url) ?? []
    
        return attemptRetryableTask(maximumRetryCount: 3) {
            let (progress, promise) = Current.shell.downloadWithAria2(
                aria2Path, 
                xcode.url,
                destination,
                cookies
            )
            progressChanged(progress)
            return promise.map { _ in destination.url }
        }
    }

    public func downloadXcodeWithURLSession(_ xcode: Xcode, to destination: Path, progressChanged: @escaping (Progress) -> Void) -> Promise<URL> {
        let resumeDataPath = Path.xcodesApplicationSupport/"Xcode-\(xcode.version).resumedata"
        let persistedResumeData = Current.files.contents(atPath: resumeDataPath.string)
        
        return attemptResumableTask(maximumRetryCount: 3) { resumeData in
            let (progress, promise) = Current.network.downloadTask(with: xcode.url,
                                                                   to: destination.url,
                                                                   resumingWith: resumeData ?? persistedResumeData)
            progressChanged(progress)
            return promise.map { $0.saveLocation }
        }
        .tap { result in
            self.persistOrCleanUpResumeData(at: resumeDataPath, for: result)
        }
    }

    public func installArchivedXcode(_ xcode: Xcode, at archiveURL: URL, to destination: Path) -> Promise<InstalledXcode> {
        let passwordInput = {
            Promise<String> { seal in
                Current.logging.log("xcodes requires superuser privileges in order to finish installation.")
                guard let password = Current.shell.readSecureLine(prompt: "macOS User Password: ") else { seal.reject(Error.missingSudoerPassword); return }
                seal.fulfill(password + "\n")
            }
        }

        return firstly { () -> Promise<InstalledXcode> in
            let destinationURL = destination.join("Xcode-\(xcode.version.descriptionWithoutBuildMetadata).app").url
            switch archiveURL.pathExtension {
            case "xip":
                return unarchiveAndMoveXIP(at: archiveURL, to: destinationURL).map { xcodeURL in
                    guard 
                        let path = Path(url: xcodeURL),
                        Current.files.fileExists(atPath: path.string),
                        let installedXcode = InstalledXcode(path: path)
                    else { throw Error.failedToMoveXcodeToDestination(destination) }
                    return installedXcode
                }
            case "dmg":
                throw Error.unsupportedFileFormat(extension: "dmg")
            default:
                throw Error.unsupportedFileFormat(extension: archiveURL.pathExtension)
            }
        }
        .then { xcode -> Promise<InstalledXcode> in
            Current.logging.log(InstallationStep.trashingArchive(archiveName: archiveURL.lastPathComponent).description)
            try Current.files.trashItem(at: archiveURL)
            Current.logging.log(InstallationStep.checkingSecurity.description)

            return when(fulfilled: self.verifySecurityAssessment(of: xcode),
                                   self.verifySigningCertificate(of: xcode.path.url))
                .map { xcode }
        }
        .then { xcode -> Promise<InstalledXcode> in
            Current.logging.log(InstallationStep.finishing.description)

            return self.enableDeveloperMode(passwordInput: passwordInput).map { xcode }
        }
        .then { xcode -> Promise<InstalledXcode> in
            self.approveLicense(for: xcode, passwordInput: passwordInput).map { xcode }
        }
        .then { xcode -> Promise<InstalledXcode> in
            self.installComponents(for: xcode, passwordInput: passwordInput).map { xcode }
        }
    }

    public func uninstallXcode(_ versionString: String, destination: Path) -> Promise<Void> {
        return firstly { () -> Promise<(InstalledXcode, URL)> in
            guard let version = Version(xcodeVersion: versionString) else {
                throw Error.invalidVersion(versionString)
            }

            guard let installedXcode = Current.files.installedXcodes(destination).first(where: { $0.version.isEqualWithoutBuildMetadataIdentifiers(to: version) }) else {
                throw Error.versionNotInstalled(version)
            }

            return Promise<URL> { seal in
                seal.fulfill(try Current.files.trashItem(at: installedXcode.path.url))
            }.map { (installedXcode, $0) }
        }
        .then { (installedXcode, trashURL) -> Promise<(InstalledXcode, URL)> in
            // If we just uninstalled the selected Xcode, try to select the latest installed version so things don't accidentally break
            Current.shell.xcodeSelectPrintPath()
                .then { output -> Promise<(InstalledXcode, URL)> in
                    if output.out.hasPrefix(installedXcode.path.string),
                       let latestInstalledXcode = Current.files.installedXcodes(destination).sorted(by: { $0.version < $1.version }).last {
                        return selectXcodeAtPath(latestInstalledXcode.path.string)
                            .map { output in
                                Current.logging.log("Selected \(output.out)")
                                return (installedXcode, trashURL)
                            }
                    }
                    else {
                        return Promise.value((installedXcode, trashURL))
                    }
                }
        }
        .done { (installedXcode, trashURL) in
            Current.logging.log("Xcode \(installedXcode.version.xcodeDescription) moved to Trash: \(trashURL.path)")
            Current.shell.exit(0)
        }
    }

    public func update() -> Promise<[Xcode]> {
//        return firstly { () -> Promise<Void> in
//            loginIfNeeded()
//        }
//        .then { () -> Promise<[Xcode]> in
            self.xcodeList.update()
//        }
    }

    public func updateAndPrint(destination: Path) -> Promise<Void> {
        update()
            .then { xcodes -> Promise<Void> in
                self.printAvailableXcodes(xcodes, installed: Current.files.installedXcodes(destination))
            }
            .done {
                Current.shell.exit(0)
            }
    }

    public func printAvailableXcodes(_ xcodes: [Xcode], installed installedXcodes: [InstalledXcode]) -> Promise<Void> {
        struct ReleasedVersion {
            let version: Version
            let releaseDate: Date?
        }

        var allXcodeVersions = xcodes.map { ReleasedVersion(version: $0.version, releaseDate: $0.releaseDate) }
        for installedXcode in installedXcodes {
            // If an installed version isn't listed online, add the installed version
            if !allXcodeVersions.contains(where: { releasedVersion in
                releasedVersion.version.isEquivalentForDeterminingIfInstalled(toInstalled: installedXcode.version)
            }) {
                allXcodeVersions.append(ReleasedVersion(version: installedXcode.version, releaseDate: nil))
            }
            // If an installed version is the same as one that's listed online which doesn't have build metadata, replace it with the installed version with build metadata
            else if let index = allXcodeVersions.firstIndex(where: { releasedVersion in
                releasedVersion.version.isEquivalentForDeterminingIfInstalled(toInstalled: installedXcode.version) &&
                releasedVersion.version.buildMetadataIdentifiers.isEmpty
            }) {
                allXcodeVersions[index] = ReleasedVersion(version: installedXcode.version, releaseDate: nil)
            }
        }
        
        return Current.shell.xcodeSelectPrintPath()
            .done { output in
                let selectedInstalledXcodeVersion = installedXcodes.first { output.out.hasPrefix($0.path.string) }.map { $0.version }

                allXcodeVersions
                    .sorted { first, second -> Bool in
                        // Sort prereleases by release date, otherwise sort by version
                        if first.version.isPrerelease, second.version.isPrerelease, let firstDate = first.releaseDate, let secondDate = second.releaseDate {
                            return firstDate < secondDate
                        }
                        return first.version < second.version
                    }
                    .forEach { releasedVersion in
                        var output = releasedVersion.version.xcodeDescription
                        if installedXcodes.contains(where: { releasedVersion.version.isEquivalentForDeterminingIfInstalled(toInstalled: $0.version) }) {
                            if releasedVersion.version == selectedInstalledXcodeVersion {
                                output += " (Installed, Selected)"
                            }
                            else {
                                output += " (Installed)"
                            }
                        }
                        Current.logging.log(output)
                    }
            }
    }
    
    public func printInstalledXcodes(destination: Path) -> Promise<Void> {
        Current.shell.xcodeSelectPrintPath()
            .done { pathOutput in
                Current.files.installedXcodes(destination)
                    .sorted { $0.version < $1.version }
                    .forEach { installedXcode in
                        var output = installedXcode.version.xcodeDescription
                        if pathOutput.out.hasPrefix(installedXcode.path.string) {
                            output += " (Selected)"
                        }
                        Current.logging.log(output)
                    }
            }
    }

    func unarchiveAndMoveXIP(at source: URL, to destination: URL) -> Promise<URL> {
        return firstly { () -> Promise<ProcessOutput> in
            Current.logging.log(InstallationStep.unarchiving.description)
            return Current.shell.unxip(source)
                .recover { (error) throws -> Promise<ProcessOutput> in
                    if case Process.PMKError.execution(_, _, let standardError) = error,
                       standardError?.contains("damaged and can’t be expanded") == true {
                        throw Error.damagedXIP(url: source)
                    }
                    throw error
                }
        }
        .map { output -> URL in
            Current.logging.log(InstallationStep.moving(destination: destination.path).description)

            let xcodeURL = source.deletingLastPathComponent().appendingPathComponent("Xcode.app")
            let xcodeBetaURL = source.deletingLastPathComponent().appendingPathComponent("Xcode-beta.app")
            if Current.files.fileExists(atPath: xcodeURL.path) {
                try Current.files.moveItem(at: xcodeURL, to: destination)
            }
            else if Current.files.fileExists(atPath: xcodeBetaURL.path) {
                try Current.files.moveItem(at: xcodeBetaURL, to: destination)
            }

            return destination
        }
    }

    public func verifySecurityAssessment(of xcode: InstalledXcode) -> Promise<Void> {
        return Current.shell.spctlAssess(xcode.path.url)
            .recover { (error: Swift.Error) throws -> Promise<ProcessOutput> in
                var output = ""
                if case let Process.PMKError.execution(_, possibleOutput, possibleError) = error {
                    output = [possibleOutput, possibleError].compactMap { $0 }.joined(separator: "\n")
                }
                throw Error.failedSecurityAssessment(xcode: xcode, output: output)
            }
            .asVoid()
    }

    func verifySigningCertificate(of url: URL) -> Promise<Void> {
        return Current.shell.codesignVerify(url)
            .recover { error -> Promise<ProcessOutput> in
                var output = ""
                if case let Process.PMKError.execution(_, possibleOutput, possibleError) = error {
                    output = [possibleOutput, possibleError].compactMap { $0 }.joined(separator: "\n")
                }
                throw Error.codesignVerifyFailed(output: output)
            }
            .map { output -> CertificateInfo in
                // codesign prints to stderr
                return self.parseCertificateInfo(output.err)
            }
            .done { cert in
                guard
                    cert.teamIdentifier == XcodeInstaller.XcodeTeamIdentifier,
                    cert.authority == XcodeInstaller.XcodeCertificateAuthority
                else { throw Error.unexpectedCodeSigningIdentity(identifier: cert.teamIdentifier, certificateAuthority: cert.authority) }
            }
    }

    public struct CertificateInfo {
        public var authority: [String]
        public var teamIdentifier: String
        public var bundleIdentifier: String
    }

    public func parseCertificateInfo(_ rawInfo: String) -> CertificateInfo {
        var info = CertificateInfo(authority: [], teamIdentifier: "", bundleIdentifier: "")

        for part in rawInfo.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines) {
            if part.hasPrefix("Authority") {
                info.authority.append(part.components(separatedBy: "=")[1])
            }
            if part.hasPrefix("TeamIdentifier") {
                info.teamIdentifier = part.components(separatedBy: "=")[1]
            }
            if part.hasPrefix("Identifier") {
                info.bundleIdentifier = part.components(separatedBy: "=")[1]
            }
        }

        return info
    }

    func enableDeveloperMode(passwordInput: @escaping () -> Promise<String>) -> Promise<Void> {
        return firstly { () -> Promise<String?> in
            Current.shell.authenticateSudoerIfNecessary(passwordInput: passwordInput)
        }
        .then { possiblePassword -> Promise<String?> in
            return Current.shell.devToolsSecurityEnable(possiblePassword).map { _ in possiblePassword }
        }
        .then { possiblePassword in
            return Current.shell.addStaffToDevelopersGroup(possiblePassword).asVoid()
        }
    }

    func approveLicense(for xcode: InstalledXcode, passwordInput: @escaping () -> Promise<String>) -> Promise<Void> {
        return firstly { () -> Promise<String?> in
            Current.shell.authenticateSudoerIfNecessary(passwordInput: passwordInput)
        }
        .then { possiblePassword in
            return Current.shell.acceptXcodeLicense(xcode, possiblePassword).asVoid()
        }
    }

    func installComponents(for xcode: InstalledXcode, passwordInput: @escaping () -> Promise<String>) -> Promise<Void> {
        return firstly { () -> Promise<String?> in
            Current.shell.authenticateSudoerIfNecessary(passwordInput: passwordInput)
        }
        .then { possiblePassword -> Promise<Void> in
            Current.shell.runFirstLaunch(xcode, possiblePassword).asVoid()
        }
        .then { () -> Promise<(String, String, String)> in
            return when(fulfilled:
                Current.shell.getUserCacheDir().map { $0.out },
                Current.shell.buildVersion().map { $0.out },
                Current.shell.xcodeBuildVersion(xcode).map { $0.out }
            )
        }
        .then { cacheDirectory, macOSBuildVersion, toolsVersion -> Promise<Void> in
            return Current.shell.touchInstallCheck(cacheDirectory, macOSBuildVersion, toolsVersion).asVoid()
        }
    }
}

private extension XcodeInstaller {
    func persistOrCleanUpResumeData<T>(at path: Path, for result: Result<T>) {
        switch result {
        case .fulfilled:
            try? Current.files.removeItem(at: path.url)
        case .rejected(let error):
            guard let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data else { return }
            Current.files.createFile(atPath: path.string, contents: resumeData)
        }
    }
}
