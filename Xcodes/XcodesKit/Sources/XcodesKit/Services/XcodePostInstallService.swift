import Foundation

public struct XcodePostInstallService: Sendable {
    public typealias RunFirstLaunch = @Sendable (InstalledXcode) async throws -> Void
    public typealias LoadShellOutput = @Sendable () async throws -> ProcessOutput
    public typealias LoadXcodeBuildVersion = @Sendable (InstalledXcode) async throws -> ProcessOutput
    public typealias TouchInstallCheck = @Sendable (String, String, String) async throws -> ProcessOutput

    private let runFirstLaunch: RunFirstLaunch
    private let getUserCacheDirectory: LoadShellOutput
    private let getMacOSBuildVersion: LoadShellOutput
    private let getXcodeBuildVersion: LoadXcodeBuildVersion
    private let touchInstallCheck: TouchInstallCheck

    public init(
        runFirstLaunch: @escaping RunFirstLaunch,
        getUserCacheDirectory: @escaping LoadShellOutput,
        getMacOSBuildVersion: @escaping LoadShellOutput,
        getXcodeBuildVersion: @escaping LoadXcodeBuildVersion,
        touchInstallCheck: @escaping TouchInstallCheck
    ) {
        self.runFirstLaunch = runFirstLaunch
        self.getUserCacheDirectory = getUserCacheDirectory
        self.getMacOSBuildVersion = getMacOSBuildVersion
        self.getXcodeBuildVersion = getXcodeBuildVersion
        self.touchInstallCheck = touchInstallCheck
    }

    public func installComponents(for xcode: InstalledXcode) async throws {
        try await runFirstLaunch(xcode)
        try Task.checkCancellation()

        async let cacheDirectory = getUserCacheDirectory().out
        async let macOSBuildVersion = getMacOSBuildVersion().out
        async let toolsVersion = getXcodeBuildVersion(xcode).out

        _ = try await touchInstallCheck(cacheDirectory, macOSBuildVersion, toolsVersion)
    }
}
