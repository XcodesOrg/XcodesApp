import Foundation
import os.log
import Security
import ServiceManagement
import XcodesKit

extension HelperClient {
    // From https://github.com/securing/SimpleXPCApp/
    func install() async throws {
        Logger.helperClient.info(#function)

        var authItem = kSMRightBlessPrivilegedHelper.withCString { name in
            AuthorizationItem(name: name, valueLength: 0, value: UnsafeMutableRawPointer(bitPattern: 0), flags: 0)
        }
        var authRights = withUnsafeMutablePointer(to: &authItem) { authItem in
            AuthorizationRights(count: 1, items: authItem)
        }

        do {
            let authRef = try authorizationRef(&authRights, nil, [.interactionAllowed, .extendRights, .preAuthorize])
            var cfError: Unmanaged<CFError>?
            // Preserve the existing privileged-helper install flow until the app can migrate to SMAppService packaging.
            legacySMJobBless(kSMDomainSystemLaunchd, machServiceName as CFString, authRef, &cfError)
            if let error = cfError?.takeRetainedValue() { throw error }

            connection?.invalidate()
            connection = nil

            Logger.helperClient.info("\(#function): Finished installation")
        } catch {
            Logger.helperClient.error("\(#function): \(error.localizedDescription)")

            throw error
        }
    }

    private func executeAuthorizationFunction(_ authorizationFunction: () -> (OSStatus)) throws {
        let osStatus = authorizationFunction()
        guard osStatus == errAuthorizationSuccess else {
            if let message = SecCopyErrorMessageString(osStatus, nil) {
                throw HelperClientError.message(String(message as NSString))
            } else {
                throw HelperClientError.message("Unknown error")
            }
        }
    }

    func authorizationRef(
        _ rights: UnsafePointer<AuthorizationRights>?,
        _ environment: UnsafePointer<AuthorizationEnvironment>?,
        _ flags: AuthorizationFlags
    ) throws -> AuthorizationRef? {
        var authRef: AuthorizationRef?
        try executeAuthorizationFunction { AuthorizationCreate(rights, environment, flags, &authRef) }
        return authRef
    }
}
