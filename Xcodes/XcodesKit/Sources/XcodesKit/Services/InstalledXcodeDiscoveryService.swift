import Foundation
@preconcurrency import Path

public struct InstalledXcodeDiscoveryService: Sendable {
    public typealias ListDirectory = @Sendable (Path) -> [Path]
    public typealias IsAppBundle = @Sendable (Path) -> Bool
    public typealias ContentsAtPath = InstalledXcode.ContentsAtPath
    public typealias LoadArchitectures = InstalledXcode.LoadArchitectures

    private let listDirectory: ListDirectory
    private let isAppBundle: IsAppBundle
    private let contentsAtPath: ContentsAtPath
    private let loadArchitectures: LoadArchitectures

    public init(
        listDirectory: @escaping ListDirectory,
        isAppBundle: @escaping IsAppBundle = { path in Path.isAppBundle(path: path) },
        contentsAtPath: @escaping ContentsAtPath,
        loadArchitectures: @escaping LoadArchitectures
    ) {
        self.listDirectory = listDirectory
        self.isAppBundle = isAppBundle
        self.contentsAtPath = contentsAtPath
        self.loadArchitectures = loadArchitectures
    }

    public func installedXcodes(in directory: Path) -> [InstalledXcode] {
        listDirectory(directory).compactMap(installedXcode(at:))
    }

    public func installedXcode(at path: Path) -> InstalledXcode? {
        guard isAppBundle(path) else { return nil }
        return InstalledXcode(
            path: path,
            contentsAtPath: contentsAtPath,
            loadArchitectures: loadArchitectures
        )
    }
}
