import Foundation
import Path
import XcodesKit

let xcodeTeamIdentifier = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_TEAM_ID") as? String ?? ""
let xcodeCertificateAuthority = ["Software Signing", "Apple Code Signing Certification Authority", "Apple Root CA"]

extension AppState {
    func verifySecurityAssessment(of xcode: InstalledXcode) async throws {
        do {
            _ = try await current.shell.spctlAssess(xcode.path.url)
        } catch {
            var output = ""
            if let executionError = error as? ProcessExecutionError {
                output = [executionError.standardOutput, executionError.standardError].joined(separator: "\n")
            }
            throw InstallationError.failedSecurityAssessment(xcode: xcode, output: output)
        }
    }

    internal func verifySigningCertificate(of url: URL) async throws {
        let output: ProcessOutput
        do {
            output = try await current.shell.codesignVerify(url)
        } catch {
            var output = ""
            if let executionError = error as? ProcessExecutionError {
                output = [executionError.standardOutput, executionError.standardError].joined(separator: "\n")
            }
            throw InstallationError.codesignVerifyFailed(output: output)
        }

        let cert = parseCertificateInfo(output.err)
        guard
            cert.teamIdentifier == xcodeTeamIdentifier,
            cert.authority == xcodeCertificateAuthority
        else {
            throw InstallationError.unexpectedCodeSigningIdentity(
                identifier: cert.teamIdentifier,
                certificateAuthority: cert.authority
            )
        }
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
