import Combine
import Foundation
import os.log
import XcodesKit

extension HelperClient {
    func switchXcodePath(_ absolutePath: String) -> AnyPublisher<Void, Error> {
        Logger.helperClient.info("\(#function): \(absolutePath, privacy: .private(mask: .hash))")

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard
            let helper = helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))")
                })
                .eraseToAnyPublisher()
        }

        return Deferred {
            Future { promise in
                helper.xcodeSelect(absolutePath: absolutePath, completion: { possibleError in
                    if let error = possibleError {
                        promise(.failure(error))
                    } else {
                        promise(.success(()))
                    }
                })
            }
        }
        .zip(connectionErrorSubject.prepend("").map { _ in () })
        .map(\.0)
        .handleEvents(
            receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0))") },
            receiveCompletion: { completion in self.log(completion: completion, function: #function) }
        )
        .eraseToAnyPublisher()
    }

    func devToolsSecurityEnable() -> AnyPublisher<Void, Error> {
        Logger.helperClient.info(#function)

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard
            let helper = helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))")
                })
                .eraseToAnyPublisher()
        }

        return Deferred {
            Future { promise in
                helper.devToolsSecurityEnable(completion: { possibleError in
                    if let error = possibleError {
                        promise(.failure(error))
                    } else {
                        promise(.success(()))
                    }
                })
            }
        }
        .zip(connectionErrorSubject.prepend("").map { _ in () })
        .map(\.0)
        .handleEvents(
            receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0))") },
            receiveCompletion: { completion in self.log(completion: completion, function: #function) }
        )
        .eraseToAnyPublisher()
    }

    func addStaffToDevelopersGroup() -> AnyPublisher<Void, Error> {
        Logger.helperClient.info(#function)

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard
            let helper = helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))")
                })
                .eraseToAnyPublisher()
        }

        return Deferred {
            Future { promise in
                helper.addStaffToDevelopersGroup(completion: { possibleError in
                    if let error = possibleError {
                        promise(.failure(error))
                    } else {
                        promise(.success(()))
                    }
                })
            }
        }
        .zip(connectionErrorSubject.prepend("").map { _ in () })
        .map(\.0)
        .handleEvents(
            receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0))") },
            receiveCompletion: { completion in self.log(completion: completion, function: #function) }
        )
        .eraseToAnyPublisher()
    }

    func acceptXcodeLicense(absoluteXcodePath: String) -> AnyPublisher<Void, Error> {
        Logger.helperClient.info("\(#function): \(absoluteXcodePath, privacy: .private(mask: .hash))")

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard
            let helper = helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))")
                })
                .eraseToAnyPublisher()
        }

        return Deferred {
            Future { promise in
                helper.acceptXcodeLicense(absoluteXcodePath: absoluteXcodePath, completion: { possibleError in
                    if let error = possibleError {
                        promise(.failure(error))
                    } else {
                        promise(.success(()))
                    }
                })
            }
        }
        .zip(connectionErrorSubject.prepend("").map { _ in () })
        .map(\.0)
        .handleEvents(
            receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0))") },
            receiveCompletion: { completion in self.log(completion: completion, function: #function) }
        )
        .eraseToAnyPublisher()
    }

    func runFirstLaunch(absoluteXcodePath: String) -> AnyPublisher<Void, Error> {
        Logger.helperClient.info("\(#function): \(absoluteXcodePath, privacy: .private(mask: .hash))")

        let connectionErrorSubject = PassthroughSubject<String, Error>()
        guard
            let helper = helper(errorSubject: connectionErrorSubject)
        else {
            return Fail(error: HelperClientError.failedToCreateRemoteObjectProxy)
                .handleEvents(receiveCompletion: { Logger.helperClient.error("\(#function): \(String(describing: $0))")
                })
                .eraseToAnyPublisher()
        }

        return Deferred {
            Future { promise in
                helper.runFirstLaunch(absoluteXcodePath: absoluteXcodePath, completion: { possibleError in
                    if let error = possibleError {
                        promise(.failure(error))
                    } else {
                        promise(.success(()))
                    }
                })
            }
        }
        .zip(connectionErrorSubject.prepend("").map { _ in () })
        .map(\.0)
        .handleEvents(
            receiveOutput: { Logger.helperClient.info("\(#function): \(String(describing: $0))") },
            receiveCompletion: { completion in self.log(completion: completion, function: #function) }
        )
        .eraseToAnyPublisher()
    }

    private func log(completion: Subscribers.Completion<Error>, function: String) {
        switch completion {
        case .finished:
            Logger.helperClient.info("\(function): finished")
        case let .failure(error):
            Logger.helperClient.error("\(function): \(String(describing: error))")
        }
    }
}
