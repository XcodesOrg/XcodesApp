import Foundation
@testable import Xcodes
import XCTest

final class XcodeBundleValidatorTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var validator: XcodeBundleValidator!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        validator = XcodeBundleValidator(requireCodeSignature: false)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
        validator = nil
    }

    func testValidateRejectsRelativePath() {
        XCTAssertThrowsError(try validator.validate(absolutePath: "Xcode.app")) { error in
            XCTAssertEqual(error as? XcodeBundleValidationError, .pathIsNotAbsolute)
        }
    }

    func testValidateRejectsNonAppDirectory() throws {
        let path = temporaryDirectory.appendingPathComponent("Xcode").path

        XCTAssertThrowsError(try validator.validate(absolutePath: path)) { error in
            XCTAssertEqual(error as? XcodeBundleValidationError, .pathIsNotAppBundle)
        }
    }

    func testValidateRejectsWrongBundleIdentifier() throws {
        let xcodeURL = try makeXcodeBundle(bundleIdentifier: "com.example.NotXcode")

        XCTAssertThrowsError(try validator.validate(absolutePath: xcodeURL.path)) { error in
            XCTAssertEqual(
                error as? XcodeBundleValidationError,
                .invalidBundleIdentifier("com.example.NotXcode")
            )
        }
    }

    func testValidateRejectsMissingXcodebuild() throws {
        let xcodeURL = try makeXcodeBundle(createXcodebuild: false)

        XCTAssertThrowsError(try validator.validate(absolutePath: xcodeURL.path)) { error in
            XCTAssertEqual(error as? XcodeBundleValidationError, .missingXcodebuild)
        }
    }

    func testValidateReturnsExpectedExecutableInsideBundle() throws {
        let xcodeURL = try makeXcodeBundle()

        let result = try validator.validate(absolutePath: xcodeURL.path)

        XCTAssertEqual(result.bundleURL, xcodeURL.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(
            result.developerDirectoryURL.path,
            xcodeURL.appendingPathComponent("Contents/Developer").path
        )
        XCTAssertEqual(
            result.xcodebuildURL.path,
            xcodeURL.appendingPathComponent("Contents/Developer/usr/bin/xcodebuild").path
        )
    }

    private func makeXcodeBundle(
        bundleIdentifier: String = XcodeBundleValidator.expectedBundleIdentifier,
        createXcodebuild: Bool = true
    ) throws -> URL {
        let xcodeURL = temporaryDirectory.appendingPathComponent("Xcode.app", isDirectory: true)
        let contentsURL = xcodeURL.appendingPathComponent("Contents", isDirectory: true)
        let developerURL = contentsURL.appendingPathComponent("Developer", isDirectory: true)
        let binURL = developerURL.appendingPathComponent("usr/bin", isDirectory: true)

        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)

        let infoPlist = [
            "CFBundleIdentifier": bundleIdentifier
        ]
        let infoPlistData = try PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0
        )
        try infoPlistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        if createXcodebuild {
            let xcodebuildURL = binURL.appendingPathComponent("xcodebuild")
            XCTAssertTrue(FileManager.default.createFile(atPath: xcodebuildURL.path, contents: Data()))
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: xcodebuildURL.path
            )
        }

        return xcodeURL
    }
}
