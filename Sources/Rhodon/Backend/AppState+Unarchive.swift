import Foundation
import Path
import RhodonKit

extension AppState {
    internal func unarchiveAndMoveXIP(
        availableXcode: AvailableXcode,
        at source: URL,
        to destination: URL
    ) async throws -> URL {
        setInstallationStep(of: availableXcode.version, to: .unarchiving)

        do {
            _ = try await unxipOrUnxipExperiment(source)
        } catch {
            if let executionError = error as? ProcessExecutionError {
                if executionError.standardError.contains("damaged and can’t be expanded") {
                    throw InstallationError.damagedXIP(url: source)
                } else if executionError.standardError
                    .contains("can’t be expanded because the selected volume doesn’t have enough free space.") {
                    guard let archivePath = Path(url: source) else {
                        throw InstallationError.failedToMoveXcodeToApplications
                    }
                    throw InstallationError.notEnoughFreeSpaceToExpandArchive(
                        archivePath: archivePath,
                        version: availableXcode.version
                    )
                }
            }
            throw error
        }

        setInstallationStep(of: availableXcode.version, to: .moving(destination: destination.path))

        let xcodeURL = source.deletingLastPathComponent().appendingPathComponent("Xcode.app")
        let xcodeBetaURL = source.deletingLastPathComponent().appendingPathComponent("Xcode-beta.app")
        if current.files.fileExists(atPath: xcodeURL.path) {
            try current.files.moveItem(at: xcodeURL, to: destination)
        } else if current.files.fileExists(atPath: xcodeBetaURL.path) {
            try current.files.moveItem(at: xcodeBetaURL, to: destination)
        }

        return destination
    }

    internal func unxipOrUnxipExperiment(_ source: URL) async throws -> ProcessOutput {
        if unxipExperiment {
            try await current.shell.unxipExperiment(source)
        } else {
            try await current.shell.unxip(source)
        }
    }
}
