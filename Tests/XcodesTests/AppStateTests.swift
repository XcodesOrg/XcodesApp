// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_length function_body_length line_length type_body_length
import AppleAPI
import Combine
import Path
import Version
@testable import Xcodes
import XcodesKit
import XCTest

private final class TestPromiseBox<Output>: @unchecked Sendable {
    typealias Promise = (Result<Output, Error>) -> Void

    private let promise: Promise

    init(_ promise: @escaping Promise) {
        self.promise = promise
    }

    func resolve(_ result: Result<Output, Error>) {
        promise(result)
    }
}

@MainActor
class AppStateTests: XCTestCase {
    var subject: AppState!
    var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        await MainActor.run {
            current = .mock
            subject = AppState()
            cancellables = []
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

    func test_VerifySecurityAssessment_Fails() throws {
        current.shell.spctlAssess = { _ in
            Fail(error: ProcessExecutionError(terminationStatus: 1, standardOutput: "stdout", standardError: "stderr"))
                .eraseToAnyPublisher()
        }

        let installedXcode = try XCTUnwrap(try InstalledXcode(path: XCTUnwrap(Path("/Applications/Xcode-0.0.0.app"))))
        let expectation = expectation(description: "Completion")
        var completion: Subscribers.Completion<Error>?
        subject.verifySecurityAssessment(of: installedXcode)
            .sink(
                receiveCompletion: {
                    completion = $0
                    expectation.fulfill()
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1)

        if case let .failure(error as InstallationError) = completion {
            XCTAssertEqual(
                error,
                InstallationError.failedSecurityAssessment(xcode: installedXcode, output: "stdout\nstderr")
            )
        } else {
            XCTFail("Expected failed security assessment error")
        }
    }

    func test_VerifySecurityAssessment_Succeeds() throws {
        current.shell.spctlAssess = { _ in
            Just(ProcessOutput(status: 0, out: "", err: ""))
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }

        let installedXcode = try XCTUnwrap(try InstalledXcode(path: XCTUnwrap(Path("/Applications/Xcode-0.0.0.app"))))
        let expectation = expectation(description: "Finished")
        subject.verifySecurityAssessment(of: installedXcode)
            .sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        XCTFail("Unexpected failure: \(error)")
                    }
                    expectation.fulfill()
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1)
    }

    func test_Install_FullHappyPath_Apple() throws {
        // Available xcode doesn't necessarily have build identifier
        subject.allXcodes = try [
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
            if path == (Path.xcodesApplicationSupport / "Xcode-0.0.0.xip").string {
                false
            } else {
                true
            }
        }
        Xcodes.current.network.validateSession = {
            Just(())
                .setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        Xcodes.current.network.dataTask = { urlRequest in
            // Don't have a valid session
            if urlRequest.url! == URLRequest.olympusSession.url! {
                return Fail(error: AuthenticationError.invalidSession)
                    .eraseToAnyPublisher()
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
                return Just(
                    (
                        data: downloadsData,
                        response: HTTPURLResponse(
                            url: urlRequest.url!,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: nil
                        )!
                    )
                )
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
            }

            return Just(
                (
                    data: Data(),
                    response: HTTPURLResponse(
                        url: urlRequest.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            )
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
        }
        // It downloads and updates progress
        let progress = Progress(totalUnitCount: 100)
        current.network.downloadTask = { url, saveLocation, _ -> (
            Progress,
            AnyPublisher<(saveLocation: URL, response: URLResponse), Error>
        ) in
            return (
                progress,
                Deferred {
                    Future { promise in
                        let promiseBox = TestPromiseBox(promise)
                        // Need this to run after the Promise has returned to the caller. This makes the test async,
                        // requiring waiting for an expectation.
                        DispatchQueue.main.async {
                            for index in 0 ... 100 {
                                progress.completedUnitCount = Int64(index)
                            }
                            promiseBox.resolve(.success((
                                saveLocation: saveLocation,
                                response: HTTPURLResponse(
                                    url: url,
                                    statusCode: 200,
                                    httpVersion: nil,
                                    headerFields: nil
                                )!
                            )))
                        }
                    }
                }
                .eraseToAnyPublisher()
            )
        }
        // It's a valid .app
        current.shell.codesignVerify = { _ in
            Just(
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
            )
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
        }
        // Helper is already installed
        subject.helperInstallState = .installed

        var allXcodesElements = [[Xcode]]()
        let installedStateExpectation = expectation(description: "Installed state")
        var didObserveInstalledState = false
        subject.$allXcodes
            .sink { xcodes in
                allXcodesElements.append(xcodes)
                if
                    !didObserveInstalledState,
                    xcodes.first?.installState == .installed(Path("/Applications/Xcode-0.0.0.app")!) {
                    didObserveInstalledState = true
                    installedStateExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        let finishedExpectation = expectation(description: "Finished")
        try subject.install(
            .version(AvailableXcode(
                version: XCTUnwrap(Version("0.0.0")),
                url: XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
                filename: "mock.xip",
                releaseDate: nil
            )),
            downloader: .urlSession
        )
        .sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    XCTFail("Unexpected failure: \(error)")
                }
                finishedExpectation.fulfill()
            },
            receiveValue: { _ in }
        )
        .store(in: &cancellables)
        wait(for: [finishedExpectation, installedStateExpectation], timeout: 5)

        XCTAssertEqual(
            allXcodesElements.map { $0.map(\.installState) },
            try [
                [XcodeInstallState.notInstalled, .notInstalled, .notInstalled],
                [.installing(.downloading(progress: progress)), .notInstalled, .notInstalled],
                [.installing(.unarchiving), .notInstalled, .notInstalled],
                [.installing(.moving(destination: "/Applications/Xcode-0.0.0.app")), .notInstalled, .notInstalled],
                [.installing(.trashingArchive), .notInstalled, .notInstalled],
                [.installing(.checkingSecurity), .notInstalled, .notInstalled],
                [.installing(.finishing), .notInstalled, .notInstalled],
                [.installed(XCTUnwrap(Path("/Applications/Xcode-0.0.0.app"))), .notInstalled, .notInstalled]
            ]
        )
    }

    func test_Install_FullHappyPath_XcodeReleases() throws {
        // Available xcode has build identifier
        subject.allXcodes = try [
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
            if path == (Path.xcodesApplicationSupport / "Xcode-0.0.0.xip").string {
                false
            } else {
                true
            }
        }
        Xcodes.current.network.dataTask = { urlRequest in
            // Don't have a valid session
            if urlRequest.url! == URLRequest.olympusSession.url! {
                return Fail(error: AuthenticationError.invalidSession)
                    .eraseToAnyPublisher()
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
                return Just(
                    (
                        data: downloadsData,
                        response: HTTPURLResponse(
                            url: urlRequest.url!,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: nil
                        )!
                    )
                )
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
            }

            return Just(
                (
                    data: Data(),
                    response: HTTPURLResponse(
                        url: urlRequest.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            )
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
        }
        // It downloads and updates progress
        let progress = Progress(totalUnitCount: 100)
        current.network.downloadTask = { url, saveLocation, _ -> (
            Progress,
            AnyPublisher<(saveLocation: URL, response: URLResponse), Error>
        ) in
            return (
                progress,
                Deferred {
                    Future { promise in
                        let promiseBox = TestPromiseBox(promise)
                        // Need this to run after the Promise has returned to the caller. This makes the test async,
                        // requiring waiting for an expectation.
                        DispatchQueue.main.async {
                            for index in 0 ... 100 {
                                progress.completedUnitCount = Int64(index)
                            }
                            promiseBox.resolve(.success((
                                saveLocation: saveLocation,
                                response: HTTPURLResponse(
                                    url: url,
                                    statusCode: 200,
                                    httpVersion: nil,
                                    headerFields: nil
                                )!
                            )))
                        }
                    }
                }
                .eraseToAnyPublisher()
            )
        }
        // It's a valid .app
        current.shell.codesignVerify = { _ in
            Just(
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
            )
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
        }
        // Helper is already installed
        subject.helperInstallState = .installed

        var allXcodesElements = [[Xcode]]()
        let installedStateExpectation = expectation(description: "Installed state")
        var didObserveInstalledState = false
        subject.$allXcodes
            .sink { xcodes in
                allXcodesElements.append(xcodes)
                if
                    !didObserveInstalledState,
                    xcodes.first?.installState == .installed(Path("/Applications/Xcode-0.0.0.app")!) {
                    didObserveInstalledState = true
                    installedStateExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        let finishedExpectation = expectation(description: "Finished")
        try subject.install(
            .version(AvailableXcode(
                version: XCTUnwrap(Version("0.0.0")),
                url: XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
                filename: "mock.xip",
                releaseDate: nil
            )),
            downloader: .urlSession
        )
        .sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    XCTFail("Unexpected failure: \(error)")
                }
                finishedExpectation.fulfill()
            },
            receiveValue: { _ in }
        )
        .store(in: &cancellables)
        wait(for: [finishedExpectation, installedStateExpectation], timeout: 5)

        XCTAssertEqual(
            allXcodesElements.map { $0.map(\.installState) },
            try [
                [XcodeInstallState.notInstalled, .notInstalled, .notInstalled],
                [.installing(.downloading(progress: progress)), .notInstalled, .notInstalled],
                [.installing(.unarchiving), .notInstalled, .notInstalled],
                [.installing(.moving(destination: "/Applications/Xcode-0.0.0.app")), .notInstalled, .notInstalled],
                [.installing(.trashingArchive), .notInstalled, .notInstalled],
                [.installing(.checkingSecurity), .notInstalled, .notInstalled],
                [.installing(.finishing), .notInstalled, .notInstalled],
                [.installed(XCTUnwrap(Path("/Applications/Xcode-0.0.0.app"))), .notInstalled, .notInstalled]
            ]
        )
    }

    func test_DownloadWithAria2_FailsWhenAria2IsUnavailable() throws {
        current.shell.aria2Path = { nil }
        current.files.fileExistsAtPath = { _ in false }

        let expectation = expectation(description: "Completion")
        var completion: Subscribers.Completion<Error>?
        try subject.downloadOrUseExistingArchive(
            for: AvailableXcode(
                version: XCTUnwrap(Version("0.0.0")),
                url: XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
                filename: "mock.xip",
                releaseDate: nil
            ),
            downloader: .aria2,
            progressChanged: { _ in }
        )
        .sink(
            receiveCompletion: {
                completion = $0
                expectation.fulfill()
            },
            receiveValue: { _ in }
        )
        .store(in: &cancellables)

        wait(for: [expectation], timeout: 1)

        guard case let .failure(error as Aria2UnavailableError) = completion else {
            return XCTFail("Expected Aria2UnavailableError")
        }

        XCTAssertEqual(error.localizedDescription, Aria2UnavailableError.installationInstructions)
    }

    func test_DownloadWithAria2_UsesSystemAria2WhenAvailable() throws {
        let aria2Path = try XCTUnwrap(Path("/usr/local/bin/aria2c"))
        current.shell.aria2Path = { aria2Path }
        current.files.fileExistsAtPath = { _ in false }

        var receivedAria2Path: Path?
        current.shell.downloadWithAria2 = { path, _, _, _ in
            receivedAria2Path = path
            return (
                Progress(),
                Just(())
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            )
        }

        let expectation = expectation(description: "Completion")
        var downloadedURL: URL?
        try subject.downloadOrUseExistingArchive(
            for: AvailableXcode(
                version: XCTUnwrap(Version("0.0.0")),
                url: XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
                filename: "mock.xip",
                releaseDate: nil
            ),
            downloader: .aria2,
            progressChanged: { _ in }
        )
        .sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    XCTFail("Unexpected failure: \(error)")
                }
                expectation.fulfill()
            },
            receiveValue: { downloadedURL = $0 }
        )
        .store(in: &cancellables)

        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(receivedAria2Path, aria2Path)
        XCTAssertEqual(downloadedURL, (Path.xcodesApplicationSupport / "Xcode-0.0.0.xip").url)
    }

    func test_Install_NotEnoughFreeSpace() throws {
        current.shell.unxip = { _ in
            Fail(error: ProcessExecutionError(
                terminationStatus: 1,
                standardOutput: "xip: signing certificate was \"Development Update\" (validation not attempted)",
                standardError: "xip: error: The archive “Xcode-12.4.0-Release.Candidate+12D4e.xip” can’t be expanded because the selected volume doesn’t have enough free space."
            ))
            .eraseToAnyPublisher()
        }
        let archiveURL = URL(fileURLWithPath: "/Users/user/Library/Application Support/Xcode-0.0.0.xip")

        let expectation = expectation(description: "Completion")
        var completion: Subscribers.Completion<Error>?
        try subject.unarchiveAndMoveXIP(
            availableXcode: AvailableXcode(
                version: XCTUnwrap(Version("0.0.0")),
                url: XCTUnwrap(URL(string: "https://developer.apple.com")),
                filename: "Xcode-0.0.0.xip",
                releaseDate: nil
            ),
            at: archiveURL,
            to: XCTUnwrap(URL(string: "/Applications/Xcode-0.0.0.app"))
        )
        .sink(
            receiveCompletion: {
                completion = $0
                expectation.fulfill()
            },
            receiveValue: { _ in }
        )
        .store(in: &cancellables)

        wait(for: [expectation], timeout: 1)

        if case let .failure(error as InstallationError) = completion {
            XCTAssertEqual(
                error,
                try InstallationError.notEnoughFreeSpaceToExpandArchive(
                    archivePath: XCTUnwrap(Path(url: archiveURL)),
                    version: XCTUnwrap(Version("0.0.0"))
                )
            )
        } else {
            XCTFail("Expected not enough free space error")
        }
    }
}
