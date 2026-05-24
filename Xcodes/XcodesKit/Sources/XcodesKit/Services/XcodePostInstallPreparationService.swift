import Foundation

public struct XcodePostInstallPreparationService: Sendable {
    public typealias EnableDeveloperTools = @Sendable () async throws -> Void
    public typealias AddStaffToDevelopersGroup = @Sendable () async throws -> Void
    public typealias AcceptLicense = @Sendable (InstalledXcode) async throws -> Void

    private let enableDeveloperTools: EnableDeveloperTools
    private let addStaffToDevelopersGroup: AddStaffToDevelopersGroup
    private let acceptLicense: AcceptLicense

    public init(
        enableDeveloperTools: @escaping EnableDeveloperTools,
        addStaffToDevelopersGroup: @escaping AddStaffToDevelopersGroup,
        acceptLicense: @escaping AcceptLicense
    ) {
        self.enableDeveloperTools = enableDeveloperTools
        self.addStaffToDevelopersGroup = addStaffToDevelopersGroup
        self.acceptLicense = acceptLicense
    }

    public func enableDeveloperMode() async throws {
        try await enableDeveloperTools()
        try await addStaffToDevelopersGroup()
    }

    public func approveLicense(for xcode: InstalledXcode) async throws {
        try await acceptLicense(xcode)
    }
}
