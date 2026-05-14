import Foundation
import os.log
import RhodonKit

extension HelperClient {
    func switchXcodePath(_ absolutePath: String) async throws {
        Logger.helperClient.info("\(#function): \(absolutePath, privacy: .private(mask: .hash))")
        try await performHelperCommand(function: #function) { helper, completion in
            helper.xcodeSelect(absolutePath: absolutePath, completion: completion)
        }
    }

    func devToolsSecurityEnable() async throws {
        Logger.helperClient.info(#function)
        try await performHelperCommand(function: #function) { helper, completion in
            helper.devToolsSecurityEnable(completion: completion)
        }
    }

    func addStaffToDevelopersGroup() async throws {
        Logger.helperClient.info(#function)
        try await performHelperCommand(function: #function) { helper, completion in
            helper.addStaffToDevelopersGroup(completion: completion)
        }
    }

    func acceptXcodeLicense(absoluteXcodePath: String) async throws {
        Logger.helperClient.info("\(#function): \(absoluteXcodePath, privacy: .private(mask: .hash))")
        try await performHelperCommand(function: #function) { helper, completion in
            helper.acceptXcodeLicense(absoluteXcodePath: absoluteXcodePath, completion: completion)
        }
    }

    func runFirstLaunch(absoluteXcodePath: String) async throws {
        Logger.helperClient.info("\(#function): \(absoluteXcodePath, privacy: .private(mask: .hash))")
        try await performHelperCommand(function: #function) { helper, completion in
            helper.runFirstLaunch(absoluteXcodePath: absoluteXcodePath, completion: completion)
        }
    }

    private func performHelperCommand(
        function: String,
        command: @escaping @Sendable (HelperXPCProtocol, @escaping (Error?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let box = ContinuationBox<Void>(continuation)
            guard let helper = helper(errorHandler: { box.resume(throwing: $0) }) else {
                box.resume(throwing: HelperClientError.failedToCreateRemoteObjectProxy)
                return
            }

            command(helper) { possibleError in
                if let possibleError {
                    Logger.helperClient.error("\(function): \(String(describing: possibleError))")
                    box.resume(throwing: possibleError)
                } else {
                    Logger.helperClient.info("\(function): finished")
                    box.resume(returning: ())
                }
            }
        }
    }
}
