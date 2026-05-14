// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_length function_body_length line_length type_body_length
import AppleAPI
import Observation
import Path
import Version
@testable import Rhodon
import RhodonKit
import XCTest

@MainActor
private func recordAllRhodon(
    from subject: AppState,
    onChange: @escaping @MainActor ([Xcode]) -> Void
) {
    onChange(subject.allRhodon)
    withObservationTracking {
        _ = subject.allRhodon
    } onChange: {
        Task {
            await recordAllRhodon(from: subject, onChange: onChange)
        }
    }
}

@MainActor
class AppStateTests: XCTestCase {
    var subject: AppState!

    override func setUp() async throws {
        await MainActor.run {
            current = .mock
            subject = AppState()
        }
    }

    func test_ParseCertificateInfo_Succeeds() {
        let sampleRawInfo = """
        Executable=/Applications/Xcode-10.1.app/Contents/MacOS/Xcode
        Identifier=com.apple.dt.Xcode
        Format=app bundle with Mach-O thin (x86_64)
        CodeDirectory v=20200 size=434 flags=0x2000(library-validation) hashes=6+5 location=embedded
        Signature size=4485
        Authority=Software Signing
        Authority=Apple Code Signing Certification Authority
        Authority=Apple Root CA
        Info.plist entries=39
        TeamIdentifier=\(xcodeTeamIdentifier)
        Sealed Resources version=2 rules=13 files=253327
        Internal requirements count=1 size=68
        """
        let info = subject.parseCertificateInfo(sampleRawInfo)

        XCTAssertEqual(
            info.authority,
            ["Software Signing", "Apple Code Signing Certification Authority", "Apple Root CA"]
        )
        XCTAssertEqual(info.teamIdentifier, xcodeTeamIdentifier)
        XCTAssertEqual(info.bundleIdentifier, "com.apple.dt.Xcode")
    }

    func test_VerifySecurityAssessment_Fails() async throws {
        current.shell.spctlAssess = { _ in
            throw ProcessExecutionError(terminationStatus: 1, standardOutput: "stdout", standardError: "stderr")
        }

        let installedXcode = try XCTUnwrap(try InstalledXcode(path: XCTUnwrap(Path("/Applications/Xcode-0.0.0.app"))))
        do {
            try await subject.verifySecurityAssessment(of: installedXcode)
            XCTFail("Expected failed security assessment error")
        } catch let error as InstallationError {
            XCTAssertEqual(
                error,
                InstallationError.failedSecurityAssessment(xcode: installedXcode, output: "stdout\nstderr")
            )
        } catch {
            XCTFail("Expected InstallationError, got \(error)")
        }
    }

    func test_VerifySecurityAssessment_Succeeds() async throws {
        current.shell.spctlAssess = { _ in
            ProcessOutput(status: 0, out: "", err: "")
        }

        let installedXcode = try XCTUnwrap(try InstalledXcode(path: XCTUnwrap(Path("/Applications/Xcode-0.0.0.app"))))
        try await subject.verifySecurityAssessment(of: installedXcode)
    }

    func test_Install_FullHappyPath_Apple() async throws {
        // Available xcode doesn't necessarily have build identifier
        subject.allRhodon = try [
            .init(version: XCTUnwrap(Version("0.0.0")), installState: .notInstalled, selected: false, icon: nil),
            .init(
                version: XCTUnwrap(Version("0.0.0-Beta.1")),
                installState: .notInstalled,
                selected: false,
                icon: nil
            ),
            .init(
                version: XCTUnwrap(Version("0.0.0-Beta.2")),
                installState: .notInstalled,
                selected: false,
                icon: nil
            )
        ]

        // It hasn't been downloaded
        current.files.fileExistsAtPath = { path in
            if path == (Path.rhodonApplicationSupport / "Xcode-0.0.0.xip").string {
                false
            } else {
                true
            }
        }
        current.network.validateSession = {
        }
        current.network.data = { urlRequest in
            // Don't have a valid session
            if urlRequest.url! == URLRequest.olympusSession.url! {
                throw AuthenticationError.invalidSession
            }
            // It's an available release version
            else if urlRequest.url! == URLRequest.downloads.url! {
                let downloads = Downloads(
                    resultCode: 0,
                    resultsString: nil,
                    downloads: [Download(
                        name: "Xcode 0.0.0",
                        files: [Download.File(remotePath: "https://apple.com/xcode.xip", fileSize: 9_484_444)],
                        dateModified: Date()
                    )]
                )
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = (try? encoder.encode(downloads)) ?? Data()
                return (
                    downloadsData,
                    HTTPURLResponse(
                        url: urlRequest.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }

            return (
                Data(),
                HTTPURLResponse(
                    url: urlRequest.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        // It downloads and updates progress
        let progress = Progress(totalUnitCount: 100)
        current.network.downloadTask = { url, saveLocation, _ in
            return (
                progress,
                Task {
                    for index in 0 ... 100 {
                        progress.completedUnitCount = Int64(index)
                    }
                    return (
                        saveLocation: saveLocation,
                        response: HTTPURLResponse(
                            url: url,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: nil
                        )!
                    )
                }
            )
        }
        // It's a valid .app
        current.shell.codesignVerify = { _ in
            ProcessOutput(
                status: 0,
                out: "",
                err: """
                TeamIdentifier=\(xcodeTeamIdentifier)
                Authority=\(xcodeCertificateAuthority[0])
                Authority=\(xcodeCertificateAuthority[1])
                Authority=\(xcodeCertificateAuthority[2])
                """
            )
        }
        // Helper is already installed
        subject.helperInstallState = .installed

        var allRhodonElements = [[Xcode]]()
        let installedStateExpectation = expectation(description: "Installed state")
        var didObserveInstalledState = false
        recordAllRhodon(from: subject) { rhodon in
            allRhodonElements.append(rhodon)
            if
                !didObserveInstalledState,
                rhodon.first?.installState == .installed(Path("/Applications/Xcode-0.0.0.app")!) {
                didObserveInstalledState = true
                installedStateExpectation.fulfill()
            }
        }
        try await subject.install(
            .version(AvailableXcode(
                version: XCTUnwrap(Version("0.0.0")),
                url: XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
                filename: "mock.xip",
                releaseDate: nil
            )),
            downloader: .urlSession
        )
        await fulfillment(of: [installedStateExpectation], timeout: 5)

        let observedStates = allRhodonElements.map { $0.map(\.installState) }
        XCTAssertTrue(observedStates.contains([.installing(.downloading(progress: progress)), .notInstalled, .notInstalled]))
        XCTAssertTrue(observedStates.contains([.installing(.finishing), .notInstalled, .notInstalled]))
        XCTAssertEqual(
            observedStates.last,
            try [.installed(XCTUnwrap(Path("/Applications/Xcode-0.0.0.app"))), .notInstalled, .notInstalled]
        )
    }

    func test_Install_FullHappyPath_XcodeReleases() async throws {
        // Available xcode has build identifier
        subject.allRhodon = try [
            .init(
                version: XCTUnwrap(Version("0.0.0+ABC123")),
                installState: .notInstalled,
                selected: false,
                icon: nil
            ),
            .init(
                version: XCTUnwrap(Version("0.0.0-Beta.1+DEF456")),
                installState: .notInstalled,
                selected: false,
                icon: nil
            ),
            .init(
                version: XCTUnwrap(Version("0.0.0-Beta.2+GHI789")),
                installState: .notInstalled,
                selected: false,
                icon: nil
            )
        ]

        // It hasn't been downloaded
        current.files.fileExistsAtPath = { path in
            if path == (Path.rhodonApplicationSupport / "Xcode-0.0.0.xip").string {
                false
            } else {
                true
            }
        }
        current.network.data = { urlRequest in
            // Don't have a valid session
            if urlRequest.url! == URLRequest.olympusSession.url! {
                throw AuthenticationError.invalidSession
            }
            // It's an available release version
            else if urlRequest.url! == URLRequest.downloads.url! {
                let downloads = Downloads(
                    resultCode: 0,
                    resultsString: nil,
                    downloads: [Download(
                        name: "Xcode 0.0.0",
                        files: [Download.File(remotePath: "https://apple.com/xcode.xip", fileSize: 9_494_944)],
                        dateModified: Date()
                    )]
                )
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = (try? encoder.encode(downloads)) ?? Data()
                return (
                    downloadsData,
                    HTTPURLResponse(
                        url: urlRequest.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }

            return (
                Data(),
                HTTPURLResponse(
                    url: urlRequest.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
        // It downloads and updates progress
        let progress = Progress(totalUnitCount: 100)
        current.network.downloadTask = { url, saveLocation, _ in
            return (
                progress,
                Task {
                    for index in 0 ... 100 {
                        progress.completedUnitCount = Int64(index)
                    }
                    return (
                        saveLocation: saveLocation,
                        response: HTTPURLResponse(
                            url: url,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: nil
                        )!
                    )
                }
            )
        }
        // It's a valid .app
        current.shell.codesignVerify = { _ in
            ProcessOutput(
                status: 0,
                out: "",
                err: """
                TeamIdentifier=\(xcodeTeamIdentifier)
                Authority=\(xcodeCertificateAuthority[0])
                Authority=\(xcodeCertificateAuthority[1])
                Authority=\(xcodeCertificateAuthority[2])
                """
            )
        }
        // Helper is already installed
        subject.helperInstallState = .installed

        var allRhodonElements = [[Xcode]]()
        let installedStateExpectation = expectation(description: "Installed state")
        var didObserveInstalledState = false
        recordAllRhodon(from: subject) { rhodon in
            allRhodonElements.append(rhodon)
            if
                !didObserveInstalledState,
                rhodon.first?.installState == .installed(Path("/Applications/Xcode-0.0.0.app")!) {
                didObserveInstalledState = true
                installedStateExpectation.fulfill()
            }
        }
        try await subject.install(
            .version(AvailableXcode(
                version: XCTUnwrap(Version("0.0.0")),
                url: XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
                filename: "mock.xip",
                releaseDate: nil
            )),
            downloader: .urlSession
        )
        await fulfillment(of: [installedStateExpectation], timeout: 5)

        let observedStates = allRhodonElements.map { $0.map(\.installState) }
        XCTAssertTrue(observedStates.contains([.installing(.downloading(progress: progress)), .notInstalled, .notInstalled]))
        XCTAssertTrue(observedStates.contains([.installing(.finishing), .notInstalled, .notInstalled]))
        XCTAssertEqual(
            observedStates.last,
            try [.installed(XCTUnwrap(Path("/Applications/Xcode-0.0.0.app"))), .notInstalled, .notInstalled]
        )
    }

    func test_DownloadWithAria2_FailsWhenAria2IsUnavailable() async throws {
        current.shell.aria2Path = { nil }
        current.files.fileExistsAtPath = { _ in false }

        do {
            _ = try await subject.downloadOrUseExistingArchive(
                for: AvailableXcode(
                    version: XCTUnwrap(Version("0.0.0")),
                    url: XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
                    filename: "mock.xip",
                    releaseDate: nil
                ),
                downloader: .aria2,
                progressChanged: { _ in }
            )
            return XCTFail("Expected Aria2UnavailableError")
        } catch let error as Aria2UnavailableError {
            XCTAssertEqual(error.localizedDescription, Aria2UnavailableError.installationInstructions)
        } catch {
            XCTFail("Expected Aria2UnavailableError, got \(error)")
        }
    }

    func test_DownloadWithAria2_UsesSystemAria2WhenAvailable() async throws {
        let aria2Path = try XCTUnwrap(Path("/usr/local/bin/aria2c"))
        current.shell.aria2Path = { aria2Path }
        current.files.fileExistsAtPath = { _ in false }

        var receivedAria2Path: Path?
        current.shell.downloadWithAria2 = { path, _, _, _ in
            receivedAria2Path = path
            return AsyncThrowingStream { continuation in
                continuation.yield(Progress())
                continuation.finish()
            }
        }

        let downloadedURL = try await subject.downloadOrUseExistingArchive(
            for: AvailableXcode(
                version: XCTUnwrap(Version("0.0.0")),
                url: XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
                filename: "mock.xip",
                releaseDate: nil
            ),
            downloader: .aria2,
            progressChanged: { _ in }
        )

        XCTAssertEqual(receivedAria2Path, aria2Path)
        XCTAssertEqual(downloadedURL, (Path.rhodonApplicationSupport / "Xcode-0.0.0.xip").url)
    }

    func test_ConfiguredAria2Process_DoesNotIncludeCookiesInArguments() throws {
        let process = configuredAria2Process(
            aria2Path: try XCTUnwrap(Path("/usr/local/bin/aria2c")),
            url: try XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
            destination: try XCTUnwrap(Path("/tmp/Xcode.xip")),
            cookies: [
                try XCTUnwrap(HTTPCookie(properties: [
                    .domain: "apple.com",
                    .path: "/",
                    .name: "ADCDownloadAuth",
                    .value: "secret-cookie-value"
                ]))
            ]
        )

        let arguments = try XCTUnwrap(process.arguments)

        XCTAssertTrue(arguments.contains("--input-file=-"))
        XCTAssertFalse(arguments.joined(separator: " ").contains("secret-cookie-value"))
        XCTAssertFalse(arguments.joined(separator: " ").contains("Cookie:"))
        XCTAssertNotNil(process.standardInput)
    }

    func test_Aria2InputFileContents_IncludesCookiesForStandardInput() throws {
        let input = aria2InputFileContents(
            url: try XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
            cookies: [
                try XCTUnwrap(HTTPCookie(properties: [
                    .domain: "apple.com",
                    .path: "/",
                    .name: "ADCDownloadAuth",
                    .value: "secret-cookie-value"
                ]))
            ]
        )

        XCTAssertEqual(input, """
        https://apple.com/xcode.xip
         header=Cookie: ADCDownloadAuth=secret-cookie-value

        """)
    }

    func test_Install_NotEnoughFreeSpace() async throws {
        current.shell.unxip = { _ in
            throw ProcessExecutionError(
                terminationStatus: 1,
                standardOutput: "xip: signing certificate was \"Development Update\" (validation not attempted)",
                standardError: "xip: error: The archive “Xcode-12.4.0-Release.Candidate+12D4e.xip” can’t be expanded because the selected volume doesn’t have enough free space."
            )
        }
        let archiveURL = URL(fileURLWithPath: "/Users/user/Library/Application Support/Xcode-0.0.0.xip")

        do {
            _ = try await subject.unarchiveAndMoveXIP(
                availableXcode: AvailableXcode(
                    version: XCTUnwrap(Version("0.0.0")),
                    url: XCTUnwrap(URL(string: "https://developer.apple.com")),
                    filename: "Xcode-0.0.0.xip",
                    releaseDate: nil
                ),
                at: archiveURL,
                to: XCTUnwrap(URL(string: "/Applications/Xcode-0.0.0.app"))
            )
            XCTFail("Expected not enough free space error")
        } catch let error as InstallationError {
            XCTAssertEqual(
                error,
                try InstallationError.notEnoughFreeSpaceToExpandArchive(
                    archivePath: XCTUnwrap(Path(url: archiveURL)),
                    version: XCTUnwrap(Version("0.0.0"))
                )
            )
        } catch {
            XCTFail("Expected InstallationError, got \(error)")
        }
    }
}
