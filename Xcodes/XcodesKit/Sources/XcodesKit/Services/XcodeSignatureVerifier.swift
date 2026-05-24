import Foundation

public struct XcodeSignature: Equatable, Sendable {
    public var authority: [String]
    public var teamIdentifier: String
    public var bundleIdentifier: String

    public init(authority: [String] = [], teamIdentifier: String = "", bundleIdentifier: String = "") {
        self.authority = authority
        self.teamIdentifier = teamIdentifier
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct XcodeSignatureVerifier: Sendable {
    public static let expectedTeamIdentifier = "59GAB85EFG"
    public static let expectedCertificateAuthority = [
        "Software Signing",
        "Apple Code Signing Certification Authority",
        "Apple Root CA",
    ]

    public init() {}

    public func parse(_ rawInfo: String) -> XcodeSignature {
        var signature = XcodeSignature()

        for line in rawInfo.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            switch parts[0] {
            case "Authority":
                signature.authority.append(String(parts[1]))
            case "TeamIdentifier":
                signature.teamIdentifier = String(parts[1])
            case "Identifier":
                signature.bundleIdentifier = String(parts[1])
            default:
                continue
            }
        }

        return signature
    }

    public func isValid(_ signature: XcodeSignature) -> Bool {
        signature.teamIdentifier == Self.expectedTeamIdentifier &&
        signature.authority == Self.expectedCertificateAuthority
    }
}
