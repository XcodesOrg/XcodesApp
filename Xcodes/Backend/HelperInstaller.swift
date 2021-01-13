// From https://github.com/securing/SimpleXPCApp/

import Foundation
import os.log
import ServiceManagement

enum HelperAuthorizationError: Error {
    case message(String)
}

class HelperInstaller {
    private static func executeAuthorizationFunction(_ authorizationFunction: () -> (OSStatus) ) throws {
        let osStatus = authorizationFunction()
        guard osStatus == errAuthorizationSuccess else {
            throw HelperAuthorizationError.message(String(describing: SecCopyErrorMessageString(osStatus, nil)))
        }
    }
    
    static func authorizationRef(_ rights: UnsafePointer<AuthorizationRights>?,
                                 _ environment: UnsafePointer<AuthorizationEnvironment>?,
                                 _ flags: AuthorizationFlags) throws -> AuthorizationRef? {
        var authRef: AuthorizationRef?
        try executeAuthorizationFunction { AuthorizationCreate(rights, environment, flags, &authRef) }
        return authRef
    }
    
    static func install() {
        var authItem = kSMRightBlessPrivilegedHelper.withCString { name in
            AuthorizationItem(name: name, valueLength: 0, value:UnsafeMutableRawPointer(bitPattern: 0), flags: 0)
        }
        var authRights = withUnsafeMutablePointer(to: &authItem) { authItem in
            AuthorizationRights(count: 1, items: authItem)
        }

        do {
            let authRef = try authorizationRef(&authRights, nil, [.interactionAllowed, .extendRights, .preAuthorize])
            var cfError: Unmanaged<CFError>?
            SMJobBless(kSMDomainSystemLaunchd, machServiceName as CFString, authRef, &cfError)
            if let error = cfError?.takeRetainedValue() { throw error }
        } catch {
            Logger.helperInstaller.error("\(error.localizedDescription)")
        }
    }
}
