import Foundation
@preconcurrency import Path
@preconcurrency import Version

public struct XcodeVersionFileService: Sendable {
    public typealias FileExists = @Sendable (String) -> Bool
    public typealias ContentsAtPath = @Sendable (String) -> Data?

    private let fileExists: FileExists
    private let contentsAtPath: ContentsAtPath

    public init(
        fileExists: @escaping FileExists = { path in FileManager.default.fileExists(atPath: path) },
        contentsAtPath: @escaping ContentsAtPath = { path in FileManager.default.contents(atPath: path) }
    ) {
        self.fileExists = fileExists
        self.contentsAtPath = contentsAtPath
    }

    /// Attempts to parse the `.xcode-version` file in the provided directory.
    public func version(inDirectory directory: Path = Path(.cwd)) -> Version? {
        let xcodeVersionFilePath = directory.join(".xcode-version")

        guard
            fileExists(xcodeVersionFilePath.string),
            let contents = contentsAtPath(xcodeVersionFilePath.string),
            let versionString = String(data: contents, encoding: .utf8)
        else {
            return nil
        }

        return Version(gemVersion: versionString)
    }
}
