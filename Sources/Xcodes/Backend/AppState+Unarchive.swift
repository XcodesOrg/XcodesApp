import Combine
import Foundation
import Path
import XcodesKit

extension AppState {
    internal func unarchiveAndMoveXIP(
        availableXcode: AvailableXcode,
        at source: URL,
        to destination: URL
    ) -> AnyPublisher<URL, Swift.Error> {
        setInstallationStep(of: availableXcode.version, to: .unarchiving)

        return unxipOrUnxipExperiment(source)
            .catch { error -> AnyPublisher<ProcessOutput, Swift.Error> in
                if let executionError = error as? ProcessExecutionError {
                    if executionError.standardError.contains("damaged and can’t be expanded") {
                        return Fail(error: InstallationError.damagedXIP(url: source))
                            .eraseToAnyPublisher()
                    } else if
                        executionError.standardError
                            .contains("can’t be expanded because the selected volume doesn’t have enough free space.") {
                        guard let archivePath = Path(url: source) else {
                            return Fail(error: InstallationError.failedToMoveXcodeToApplications)
                                .eraseToAnyPublisher()
                        }
                        return Fail(error: InstallationError.notEnoughFreeSpaceToExpandArchive(
                            archivePath: archivePath,
                            version: availableXcode.version
                        ))
                        .eraseToAnyPublisher()
                    }
                }
                return Fail(error: error)
                    .eraseToAnyPublisher()
            }
            .tryMap { _ -> URL in
                self.setInstallationStep(of: availableXcode.version, to: .moving(destination: destination.path))

                let xcodeURL = source.deletingLastPathComponent().appendingPathComponent("Xcode.app")
                let xcodeBetaURL = source.deletingLastPathComponent().appendingPathComponent("Xcode-beta.app")
                if current.files.fileExists(atPath: xcodeURL.path) {
                    try current.files.moveItem(at: xcodeURL, to: destination)
                } else if current.files.fileExists(atPath: xcodeBetaURL.path) {
                    try current.files.moveItem(at: xcodeBetaURL, to: destination)
                }

                return destination
            }
            .handleEvents(receiveCancel: {
                if current.files.fileExists(atPath: source.path) {
                    try? current.files.removeItem(source)
                }
                if current.files.fileExists(atPath: destination.path) {
                    try? current.files.removeItem(destination)
                }
            })
            .eraseToAnyPublisher()
    }

    internal func unxipOrUnxipExperiment(_ source: URL) -> AnyPublisher<ProcessOutput, Error> {
        if unxipExperiment {
            // All hard work done by https://github.com/saagarjha/unxip via libunxip.
            current.shell.unxipExperiment(source)
        } else {
            current.shell.unxip(source)
        }
    }
}
