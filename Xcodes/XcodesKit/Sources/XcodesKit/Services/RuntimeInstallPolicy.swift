import Foundation
@preconcurrency import Version

public enum RuntimeInstallMethod: Equatable, Sendable {
    case archive
    case xcodebuild(architecture: String?)
}

public enum RuntimeInstallPolicyError: LocalizedError, Equatable, Sendable {
    case noSelectedXcode
    case xcode16_1OrGreaterRequired(Version)
    case xcode26OrGreaterRequired(Version)

    public var errorDescription: String? {
        switch self {
        case .noSelectedXcode:
            return "No Xcode is currently selected, please make sure that you have one selected and installed before trying to install this runtime"
        case let .xcode16_1OrGreaterRequired(version):
            return "Installing this runtime requires Xcode 16.1 or greater to be selected, but is currently \(version.description)"
        case let .xcode26OrGreaterRequired(version):
            return "Installing this runtime for Apple Silicon requires Xcode 26 or greater to be selected, but is currently \(version.description)"
        }
    }
}

public struct RuntimeInstallPolicy: Sendable {
    public init() {}

    public func installMethod(
        for runtime: DownloadableRuntime,
        selectedXcodeVersion: Version?
    ) throws -> RuntimeInstallMethod {
        guard runtime.contentType == .cryptexDiskImage else {
            return .archive
        }

        guard let selectedXcodeVersion else {
            throw RuntimeInstallPolicyError.noSelectedXcode
        }

        guard selectedXcodeVersion > Version(major: 16, minor: 0, patch: 0) else {
            throw RuntimeInstallPolicyError.xcode16_1OrGreaterRequired(selectedXcodeVersion)
        }

        if runtime.architectures?.isAppleSilicon == true {
            guard selectedXcodeVersion > Version(major: 25, minor: 0, patch: 0) else {
                throw RuntimeInstallPolicyError.xcode26OrGreaterRequired(selectedXcodeVersion)
            }
            return .xcodebuild(architecture: Architecture.arm64.rawValue)
        }

        return .xcodebuild(architecture: nil)
    }

    public func selectedXcodeVersion(fromXcodebuildVersionOutput output: String) -> Version? {
        let versionPattern = #"Xcode (\d+\.\d+)"#
        guard let versionRegex = try? NSRegularExpression(pattern: versionPattern),
              let match = versionRegex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let versionRange = Range(match.range(at: 1), in: output) else {
            return nil
        }

        return Version(tolerant: String(output[versionRange]))
    }
}
