import Foundation
@preconcurrency import Path

public struct RuntimePackageInstallService: Sendable {
    public typealias ProcessOperation = @Sendable (URL, URL) async throws -> ProcessOutput
    public typealias InstallPackage = @Sendable (URL, String) async throws -> ProcessOutput

    private let mountDMG: @Sendable (URL) async throws -> URL
    private let unmountDMG: @Sendable (URL) async throws -> Void
    private let packagePath: @Sendable (URL) throws -> Path
    private let prepareDirectory: @Sendable (Path) throws -> Void
    private let expandPkg: ProcessOperation
    private let createPkg: ProcessOperation
    private let installPkg: InstallPackage
    private let contentsAtPath: @Sendable (String) -> Data?
    private let writeData: @Sendable (Data, URL) throws -> Void
    private let removeItem: @Sendable (URL) throws -> Void

    public init(
        mountDMG: @escaping @Sendable (URL) async throws -> URL,
        unmountDMG: @escaping @Sendable (URL) async throws -> Void,
        packagePath: @escaping @Sendable (URL) throws -> Path = { mountedURL in
            guard let mountedPath = Path(url: mountedURL), let packagePath = mountedPath.ls().first else {
                throw XcodesKitError("Could not find runtime package in mounted disk image.")
            }
            return packagePath
        },
        prepareDirectory: @escaping @Sendable (Path) throws -> Void = { path in
            try path.mkdir().setCurrentUserAsOwner()
        },
        expandPkg: @escaping ProcessOperation,
        createPkg: @escaping ProcessOperation,
        installPkg: @escaping InstallPackage,
        contentsAtPath: @escaping @Sendable (String) -> Data?,
        writeData: @escaping @Sendable (Data, URL) throws -> Void,
        removeItem: @escaping @Sendable (URL) throws -> Void
    ) {
        self.mountDMG = mountDMG
        self.unmountDMG = unmountDMG
        self.packagePath = packagePath
        self.prepareDirectory = prepareDirectory
        self.expandPkg = expandPkg
        self.createPkg = createPkg
        self.installPkg = installPkg
        self.contentsAtPath = contentsAtPath
        self.writeData = writeData
        self.removeItem = removeItem
    }

    public func installPackageRuntime(
        from diskImageURL: URL,
        runtime: DownloadableRuntime,
        cachesDirectory: Path
    ) async throws {
        let mountedURL = try await mountDMG(diskImageURL)
        var didUnmount = false

        do {
            let mountedPackagePath = try packagePath(mountedURL)

            try prepareDirectory(cachesDirectory)

            let expandedPkgPath = cachesDirectory/runtime.identifier
            try? removeItem(expandedPkgPath.url)
            _ = try await expandPkg(mountedPackagePath.url, expandedPkgPath.url)

            try await unmountDMG(mountedURL)
            didUnmount = true

            let packageInfoPath = expandedPkgPath/"PackageInfo"
            guard let packageInfoData = contentsAtPath(packageInfoPath.string),
                  var packageInfoContents = String(data: packageInfoData, encoding: .utf8) else {
                throw XcodesKitError("Could not read PackageInfo for \(runtime.visibleIdentifier).")
            }

            let runtimeDestination = runtimeDestinationPath(for: runtime)
            packageInfoContents = packageInfoContents.replacingOccurrences(
                of: "<pkg-info",
                with: "<pkg-info install-location=\"\(runtimeDestination.string)\""
            )
            try writeData(Data(packageInfoContents.utf8), packageInfoPath.url)

            let newPkgPath = cachesDirectory/(runtime.identifier + ".pkg")
            try? removeItem(newPkgPath.url)
            _ = try await createPkg(expandedPkgPath.url, newPkgPath.url)
            try removeItem(expandedPkgPath.url)

            _ = try await installPkg(newPkgPath.url, "/")
            try removeItem(newPkgPath.url)
        } catch {
            if !didUnmount {
                try? await unmountDMG(mountedURL)
            }
            throw error
        }
    }

    public func runtimeDestinationPath(for runtime: DownloadableRuntime) -> Path {
        let runtimeFileName = "\(runtime.visibleIdentifier).simruntime"
        return Path("/Library/Developer/CoreSimulator/Profiles/Runtimes/\(runtimeFileName)")!
    }
}
