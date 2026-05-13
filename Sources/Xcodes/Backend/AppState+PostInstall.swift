import Combine
import Foundation
import os.log
import Path
import XcodesKit

extension AppState {
    /// Attemps to install the helper once, then performs all post-install steps
    func performPostInstallSteps(for xcode: InstalledXcode) {
        performPostInstallSteps(for: xcode)
            .sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        self.error = error
                        self.presentedAlert = .generic(
                            title: "Unable to perform post install steps",
                            message: error.legibleLocalizedDescription
                        )
                    }
                },
                receiveValue: {}
            )
            .store(in: &cancellables)
    }

    /// Attemps to install the helper once, then performs all post-install steps
    func performPostInstallSteps(for xcode: InstalledXcode) -> AnyPublisher<Void, Error> {
        let postInstallPublisher: AnyPublisher<Void, Error> =
            Deferred { [unowned self] in
                installHelperIfNecessary()
            }
            .flatMap { [unowned self] in
                enableDeveloperMode()
            }
            .flatMap { [unowned self] in
                approveLicense(for: xcode)
            }
            .flatMap { [unowned self] in
                installComponents(for: xcode)
            }
            .mapError { [unowned self] error in
                Logger.appState.error("Performing post-install steps failed: \(error.legibleLocalizedDescription)")
                return InstallationError.postInstallStepsNotPerformed(
                    version: xcode.version,
                    helperInstallState: helperInstallState
                )
            }
            .eraseToAnyPublisher()

        guard helperInstallState == .installed else {
            let helperInstallConsentSubject = PassthroughSubjectBox<Void, Error>()

            DispatchQueue.main.async {
                self.isPreparingUserForActionRequiringHelper = { [unowned self] userConsented in
                    if userConsented {
                        helperInstallConsentSubject.send(())
                    } else {
                        Logger.appState.info("User did not consent to installing helper during post-install steps.")

                        helperInstallConsentSubject.send(
                            completion: .failure(
                                InstallationError.postInstallStepsNotPerformed(
                                    version: xcode.version,
                                    helperInstallState: helperInstallState
                                )
                            )
                        )
                    }
                }
                self.presentedAlert = .privilegedHelper
            }

            unxipProgress.completedUnitCount = AppState.totalProgressUnits
            resetDockProgressTracking()

            return helperInstallConsentSubject.publisher
                .flatMap {
                    postInstallPublisher
                }
                .eraseToAnyPublisher()
        }

        return postInstallPublisher
    }

    private func enableDeveloperMode() -> AnyPublisher<Void, Error> {
        current.helper.devToolsSecurityEnable()
            .flatMap {
                current.helper.addStaffToDevelopersGroup()
            }
            .eraseToAnyPublisher()
    }

    private func approveLicense(for xcode: InstalledXcode) -> AnyPublisher<Void, Error> {
        current.helper.acceptXcodeLicense(xcode.path.string)
            .eraseToAnyPublisher()
    }

    private func installComponents(for xcode: InstalledXcode) -> AnyPublisher<Void, Swift.Error> {
        current.helper.runFirstLaunch(xcode.path.string)
            .flatMap {
                current.shell.getUserCacheDir().map(\.out)
                    .combineLatest(
                        current.shell.buildVersion().map(\.out),
                        current.shell.xcodeBuildVersion(xcode).map(\.out)
                    )
            }
            .flatMap { cacheDirectory, macOSBuildVersion, toolsVersion in
                current.shell.touchInstallCheck(cacheDirectory, macOSBuildVersion, toolsVersion)
            }
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}
