import Combine
import Foundation
import Path
import XcodesKit

let xcodeTeamIdentifier = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_TEAM_ID") as? String ?? ""
let xcodeCertificateAuthority = ["Software Signing", "Apple Code Signing Certification Authority", "Apple Root CA"]

extension AppState {
    func verifySecurityAssessment(of xcode: InstalledXcode) -> AnyPublisher<Void, Error> {
        current.shell.spctlAssess(xcode.path.url)
            .catch { (error: Swift.Error) -> AnyPublisher<ProcessOutput, Error> in
                var output = ""
                if let executionError = error as? ProcessExecutionError {
                    output = [executionError.standardOutput, executionError.standardError].joined(separator: "\n")
                }
                return Fail(error: InstallationError.failedSecurityAssessment(xcode: xcode, output: output))
                    .eraseToAnyPublisher()
            }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    internal func verifySigningCertificate(of url: URL) -> AnyPublisher<Void, Error> {
        current.shell.codesignVerify(url)
            .catch { error -> AnyPublisher<ProcessOutput, Error> in
                var output = ""
                if let executionError = error as? ProcessExecutionError {
                    output = [executionError.standardOutput, executionError.standardError].joined(separator: "\n")
                }
                return Fail(error: InstallationError.codesignVerifyFailed(output: output))
                    .eraseToAnyPublisher()
            }
            .map { output -> CertificateInfo in
                // codesign prints to stderr
                return self.parseCertificateInfo(output.err)
            }
            .tryMap { cert in
                guard
                    cert.teamIdentifier == xcodeTeamIdentifier,
                    cert.authority == xcodeCertificateAuthority
                else { throw InstallationError.unexpectedCodeSigningIdentity(
                    identifier: cert.teamIdentifier,
                    certificateAuthority: cert.authority
                ) }

                return ()
            }
            .eraseToAnyPublisher()
    }

    struct CertificateInfo {
        public var authority: [String]
        public var teamIdentifier: String
        public var bundleIdentifier: String
    }

    func parseCertificateInfo(_ rawInfo: String) -> CertificateInfo {
        var info = CertificateInfo(authority: [], teamIdentifier: "", bundleIdentifier: "")

        for part in rawInfo.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines) {
            if part.hasPrefix("Authority") {
                info.authority.append(part.components(separatedBy: "=")[1])
            }
            if part.hasPrefix("TeamIdentifier") {
                info.teamIdentifier = part.components(separatedBy: "=")[1]
            }
            if part.hasPrefix("Identifier") {
                info.bundleIdentifier = part.components(separatedBy: "=")[1]
            }
        }

        return info
    }
}
