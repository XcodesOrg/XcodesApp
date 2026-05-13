import Foundation
import Security

struct XcodeBundleValidationResult: Equatable {
    let bundleURL: URL
    let developerDirectoryURL: URL
    let xcodebuildURL: URL
}

enum XcodeBundleValidationError: Error, Equatable {
    case pathIsNotAbsolute
    case pathIsNotDirectory
    case pathIsNotAppBundle
    case missingInfoPlist
    case invalidBundleIdentifier(String?)
    case missingDeveloperDirectory
    case missingXcodebuild
    case invalidCodeSignature
}

struct XcodeBundleValidator {
    static let expectedBundleIdentifier = "com.apple.dt.Xcode"

    private let fileManager: FileManager
    private let requireCodeSignature: Bool

    init(fileManager: FileManager = .default, requireCodeSignature: Bool = true) {
        self.fileManager = fileManager
        self.requireCodeSignature = requireCodeSignature
    }

    func validate(absolutePath: String) throws -> XcodeBundleValidationResult {
        guard (absolutePath as NSString).isAbsolutePath else {
            throw XcodeBundleValidationError.pathIsNotAbsolute
        }

        let url = URL(fileURLWithPath: absolutePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        guard url.pathExtension == "app" else {
            throw XcodeBundleValidationError.pathIsNotAppBundle
        }

        guard directoryExists(at: url) else {
            throw XcodeBundleValidationError.pathIsNotDirectory
        }

        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let infoPlistData = try? Data(contentsOf: infoPlistURL) else {
            throw XcodeBundleValidationError.missingInfoPlist
        }

        let propertyList = try? PropertyListSerialization.propertyList(
            from: infoPlistData,
            options: [],
            format: nil
        )
        guard let infoPlist = propertyList as? [String: Any] else {
            throw XcodeBundleValidationError.missingInfoPlist
        }

        let bundleIdentifier = infoPlist["CFBundleIdentifier"] as? String
        guard bundleIdentifier == Self.expectedBundleIdentifier else {
            throw XcodeBundleValidationError.invalidBundleIdentifier(bundleIdentifier)
        }

        let developerDirectoryURL = url.appendingPathComponent("Contents/Developer").standardizedFileURL
        guard directoryExists(at: developerDirectoryURL) else {
            throw XcodeBundleValidationError.missingDeveloperDirectory
        }

        let xcodebuildURL = developerDirectoryURL
            .appendingPathComponent("usr/bin/xcodebuild")
            .standardizedFileURL
        guard isExecutableFile(at: xcodebuildURL) else {
            throw XcodeBundleValidationError.missingXcodebuild
        }

        guard !requireCodeSignature || hasValidAppleXcodeSignature(at: url) else {
            throw XcodeBundleValidationError.invalidCodeSignature
        }

        return XcodeBundleValidationResult(
            bundleURL: url,
            developerDirectoryURL: developerDirectoryURL,
            xcodebuildURL: xcodebuildURL
        )
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func isExecutableFile(at url: URL) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
    }

    private func hasValidAppleXcodeSignature(at url: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess else {
            return false
        }

        guard let staticCode else {
            return false
        }

        let requirementString = "identifier \"\(Self.expectedBundleIdentifier)\" and anchor apple generic" as CFString
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(
            requirementString,
            SecCSFlags(rawValue: 0),
            &requirement
        )
        guard status == errSecSuccess, let requirement else {
            return false
        }

        return SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: 0), requirement) == errSecSuccess
    }
}
