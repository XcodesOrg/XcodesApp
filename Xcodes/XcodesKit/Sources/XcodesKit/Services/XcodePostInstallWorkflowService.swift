import Foundation

public struct XcodePostInstallWorkflowService: Sendable {
    public typealias EnableDeveloperMode = @Sendable () async throws -> Void
    public typealias ApproveLicense = @Sendable (InstalledXcode) async throws -> Void
    public typealias InstallComponents = @Sendable (InstalledXcode) async throws -> Void

    private let enableDeveloperMode: EnableDeveloperMode
    private let approveLicense: ApproveLicense
    private let installComponents: InstallComponents

    public init(
        preparationService: XcodePostInstallPreparationService,
        postInstallService: XcodePostInstallService
    ) {
        self.init(
            enableDeveloperMode: { try await preparationService.enableDeveloperMode() },
            approveLicense: { try await preparationService.approveLicense(for: $0) },
            installComponents: { try await postInstallService.installComponents(for: $0) }
        )
    }

    public init(
        enableDeveloperMode: @escaping EnableDeveloperMode,
        approveLicense: @escaping ApproveLicense,
        installComponents: @escaping InstallComponents
    ) {
        self.enableDeveloperMode = enableDeveloperMode
        self.approveLicense = approveLicense
        self.installComponents = installComponents
    }

    public func performPostInstallSteps(for xcode: InstalledXcode) async throws {
        try await enableDeveloperMode()
        try Task.checkCancellation()
        try await approveLicense(xcode)
        try Task.checkCancellation()
        try await installComponents(xcode)
    }
}
