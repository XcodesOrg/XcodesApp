import Foundation
import os.log
import Path
import RhodonKit

extension AppState {
    /// Attempts to install the helper once, then performs all post-install steps.
    func performPostInstallSteps(for xcode: InstalledXcode) async throws {
        guard helperInstallState == .installed else {
            isPreparingUserForActionRequiringHelper = { [unowned self] userConsented in
                guard userConsented else {
                    Logger.appState.info("User did not consent to installing helper during post-install steps.")
                    self.error = InstallationError.postInstallStepsNotPerformed(
                        version: xcode.version,
                        helperInstallState: helperInstallState
                    )
                    return
                }

                do {
                    try await self.performPostInstallSteps(for: xcode)
                } catch {
                    self.error = error
                }
            }
            presentedAlert = .privilegedHelper
            unxipProgress.completedUnitCount = AppState.totalProgressUnits
            resetDockProgressTracking()
            throw InstallationError.postInstallStepsNotPerformed(
                version: xcode.version,
                helperInstallState: helperInstallState
            )
        }

        do {
            try await installHelperIfNecessary()
            try await enableDeveloperMode()
            try await approveLicense(for: xcode)
            try await installComponents(for: xcode)
        } catch {
            Logger.appState.error("Performing post-install steps failed: \(error.legibleLocalizedDescription)")
            throw InstallationError.postInstallStepsNotPerformed(
                version: xcode.version,
                helperInstallState: helperInstallState
            )
        }
    }

    private func enableDeveloperMode() async throws {
        try await current.helper.devToolsSecurityEnable()
        try await current.helper.addStaffToDevelopersGroup()
    }

    private func approveLicense(for xcode: InstalledXcode) async throws {
        try await current.helper.acceptXcodeLicense(xcode.path.string)
    }

    private func installComponents(for xcode: InstalledXcode) async throws {
        try await current.helper.runFirstLaunch(xcode.path.string)
        async let cacheDirectoryOutput = current.shell.getUserCacheDir()
        async let macOSBuildVersionOutput = current.shell.buildVersion()
        async let toolsVersionOutput = current.shell.xcodeBuildVersion(xcode)
        let (cacheDirectory, macOSBuildVersion, toolsVersion) = try await (
            cacheDirectoryOutput.out,
            macOSBuildVersionOutput.out,
            toolsVersionOutput.out
        )
        _ = try await current.shell.touchInstallCheck(cacheDirectory, macOSBuildVersion, toolsVersion)
    }
}
