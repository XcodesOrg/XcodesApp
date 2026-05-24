import Foundation
@preconcurrency import Path

public enum XcodeArchiveInstallError: Error, Equatable, Sendable {
    case failedToMoveXcodeToDestination(Path)
    case unsupportedFileFormat(extension: String)
}

public enum XcodeArchiveInstallStep: Equatable, Sendable {
    case unarchive(XcodeUnarchiveStep)
    case cleaningArchive(archiveName: String)
    case checkingSecurity
}

public struct XcodeArchiveInstallService: Sendable {
    public typealias CleanArchive = @Sendable (URL) throws -> Void
    public typealias StepChanged = @Sendable (XcodeArchiveInstallStep) async -> Void
    public typealias MakeInstalledXcode = @Sendable (Path) -> InstalledXcode?

    private let destinationDirectory: Path
    private let unarchiveService: XcodeUnarchiveService
    private let validationService: XcodeValidationService
    private let fileExists: @Sendable (String) -> Bool
    private let makeInstalledXcode: MakeInstalledXcode

    public init(
        destinationDirectory: Path,
        unarchiveService: XcodeUnarchiveService,
        validationService: XcodeValidationService,
        fileExists: @escaping @Sendable (String) -> Bool,
        makeInstalledXcode: @escaping MakeInstalledXcode
    ) {
        self.destinationDirectory = destinationDirectory
        self.unarchiveService = unarchiveService
        self.validationService = validationService
        self.fileExists = fileExists
        self.makeInstalledXcode = makeInstalledXcode
    }

    public func installArchivedXcode(
        _ xcode: AvailableXcode,
        at archiveURL: URL,
        cleanArchive: @escaping CleanArchive,
        stepChanged: @escaping StepChanged = { _ in }
    ) async throws -> InstalledXcode {
        guard archiveURL.pathExtension == "xip" else {
            throw XcodeArchiveInstallError.unsupportedFileFormat(extension: archiveURL.pathExtension)
        }

        let destinationURL = destinationDirectory
            .join("Xcode-\(xcode.version.descriptionWithoutBuildMetadata).app")
            .url

        let xcodeURL = try await unarchiveService.unarchiveAndMoveXIP(at: archiveURL, to: destinationURL) { step in
            await stepChanged(.unarchive(step))
        }

        guard
            let path = Path(url: xcodeURL),
            fileExists(path.string),
            let installedXcode = makeInstalledXcode(path)
        else {
            throw XcodeArchiveInstallError.failedToMoveXcodeToDestination(destinationDirectory)
        }

        await stepChanged(.cleaningArchive(archiveName: archiveURL.lastPathComponent))
        try cleanArchive(archiveURL)

        await stepChanged(.checkingSecurity)
        async let securityAssessment: Void = validationService.verifySecurityAssessment(of: installedXcode)
        async let signingCertificate: Void = validationService.verifySigningCertificate(of: installedXcode.path.url)
        _ = try await (securityAssessment, signingCertificate)

        return installedXcode
    }
}
