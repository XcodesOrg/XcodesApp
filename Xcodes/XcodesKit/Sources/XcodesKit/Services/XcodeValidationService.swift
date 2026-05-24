import Foundation

public enum XcodeValidationError: Error, Equatable, Sendable {
    case failedSecurityAssessment(xcode: InstalledXcode, output: String)
    case codesignVerifyFailed(output: String)
    case unexpectedCodeSigningIdentity(identifier: String, certificateAuthority: [String])
}

public struct XcodeValidationService: Sendable {
    public typealias AssessSecurity = @Sendable (URL) async throws -> ProcessOutput
    public typealias VerifyCodesign = @Sendable (URL) async throws -> ProcessOutput

    private let assessSecurity: AssessSecurity
    private let verifyCodesign: VerifyCodesign
    private let signatureVerifier: XcodeSignatureVerifier

    public init(
        assessSecurity: @escaping AssessSecurity,
        verifyCodesign: @escaping VerifyCodesign,
        signatureVerifier: XcodeSignatureVerifier = XcodeSignatureVerifier()
    ) {
        self.assessSecurity = assessSecurity
        self.verifyCodesign = verifyCodesign
        self.signatureVerifier = signatureVerifier
    }

    public func verifySecurityAssessment(of xcode: InstalledXcode) async throws {
        do {
            _ = try await assessSecurity(xcode.path.url)
        } catch {
            throw XcodeValidationError.failedSecurityAssessment(
                xcode: xcode,
                output: Self.processOutput(from: error)
            )
        }
    }

    public func verifySigningCertificate(of url: URL) async throws {
        let output: ProcessOutput
        do {
            output = try await verifyCodesign(url)
        } catch {
            throw XcodeValidationError.codesignVerifyFailed(output: Self.processOutput(from: error))
        }

        let signature = signatureVerifier.parse(output.err)
        guard signatureVerifier.isValid(signature) else {
            throw XcodeValidationError.unexpectedCodeSigningIdentity(
                identifier: signature.teamIdentifier,
                certificateAuthority: signature.authority
            )
        }
    }

    private static func processOutput(from error: Error) -> String {
        guard let executionError = error as? ProcessExecutionError else { return "" }
        return [executionError.standardOutput, executionError.standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
