import Foundation
@preconcurrency import Path

public enum XcodeSelectionFilesystemError: LocalizedError, Equatable, Sendable {
    case destinationExistsAndIsNotSymlink(Path)

    public var errorDescription: String? {
        switch self {
        case let .destinationExistsAndIsNotSymlink(path):
            return "A non-symbolic-link item already exists at \(path.string)."
        }
    }
}

public struct XcodeSelectionFilesystemService: Sendable {
    public typealias FileExists = @Sendable (String) -> Bool
    public typealias AttributesOfItem = @Sendable (String) throws -> [FileAttributeKey: Any]
    public typealias RemoveItem = @Sendable (String) throws -> Void
    public typealias CreateSymbolicLink = @Sendable (String, String) throws -> Void
    public typealias InstalledXcodeAtPath = @Sendable (Path) -> InstalledXcode?
    public typealias Rename = @Sendable (Path, String) throws -> Path

    public struct SymbolicLinkResult: Equatable, Sendable {
        public let destinationPath: Path
        public let replacedExistingSymlink: Bool
    }

    private let fileExists: FileExists
    private let attributesOfItem: AttributesOfItem
    private let removeItem: RemoveItem
    private let createSymbolicLink: CreateSymbolicLink
    private let installedXcode: InstalledXcodeAtPath
    private let rename: Rename

    public init(
        fileExists: @escaping FileExists = { path in FileManager.default.fileExists(atPath: path) },
        attributesOfItem: @escaping AttributesOfItem = { path in try FileManager.default.attributesOfItem(atPath: path) },
        removeItem: @escaping RemoveItem = { path in try FileManager.default.removeItem(atPath: path) },
        createSymbolicLink: @escaping CreateSymbolicLink = { path, destination in
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: destination)
        },
        installedXcode: @escaping InstalledXcodeAtPath,
        rename: @escaping Rename = { try $0.rename(to: $1) }
    ) {
        self.fileExists = fileExists
        self.attributesOfItem = attributesOfItem
        self.removeItem = removeItem
        self.createSymbolicLink = createSymbolicLink
        self.installedXcode = installedXcode
        self.rename = rename
    }

    public func createSymbolicLink(
        to installedXcodePath: Path,
        in installDirectory: Path,
        isBeta: Bool = false
    ) throws -> SymbolicLinkResult {
        let destinationPath = installDirectory/"Xcode\(isBeta ? "-Beta" : "").app"
        var replacedExistingSymlink = false

        if fileExists(destinationPath.string) {
            let attributes = try attributesOfItem(destinationPath.string)
            if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                try removeItem(destinationPath.string)
                replacedExistingSymlink = true
            } else {
                throw XcodeSelectionFilesystemError.destinationExistsAndIsNotSymlink(destinationPath)
            }
        }

        try createSymbolicLink(destinationPath.string, installedXcodePath.string)
        return SymbolicLinkResult(destinationPath: destinationPath, replacedExistingSymlink: replacedExistingSymlink)
    }

    public func renameForSelection(
        installedXcodePath: Path,
        in installDirectory: Path
    ) throws -> Path {
        let destinationPath = installDirectory/"Xcode.app"

        if fileExists(destinationPath.string), let originalXcode = installedXcode(destinationPath) {
            let newName = "Xcode-\(originalXcode.version.descriptionWithoutBuildMetadata).app"
            _ = try rename(destinationPath, newName)
        }

        return try rename(installedXcodePath, "Xcode.app")
    }
}
