import XcodesLoginKit
import Combine
import CombineExpectations
import Path
import Version
import XCTest
import XcodesKit

@testable import Xcodes

class AppStateTests: XCTestCase {
    var subject: AppState!
    
    override func setUpWithError() throws {
        Current = .mock
        subject = AppState()
    }
    
    func test_ParseCertificateInfo_Succeeds() throws {
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
        TeamIdentifier=59GAB85EFG
        Sealed Resources version=2 rules=13 files=253327
        Internal requirements count=1 size=68
        """
        let info = subject.parseCertificateInfo(sampleRawInfo)

        XCTAssertEqual(info.authority, ["Software Signing", "Apple Code Signing Certification Authority", "Apple Root CA"])
        XCTAssertEqual(info.teamIdentifier, "59GAB85EFG")
        XCTAssertEqual(info.bundleIdentifier, "com.apple.dt.Xcode")
    }

    func test_VerifySecurityAssessment_Fails() throws {
        Current.shell.spctlAssess = { _ in
            Fail(error: ProcessExecutionError(process: Process(), standardOutput: "stdout", standardError: "stderr")) 
                .eraseToAnyPublisher()
        }

        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
        let recorder = subject.verifySecurityAssessment(of: installedXcode).record()
        let completion = try wait(for: recorder.completion, timeout: 1, description: "Completion")

        if case let .failure(error as InstallationError) = completion { 
            XCTAssertEqual(error, InstallationError.failedSecurityAssessment(xcode: installedXcode, output: "stdout\nstderr"))
        }
        else {
            XCTFail() 
        }
    }

    func test_VerifySecurityAssessment_Succeeds() throws {
        Current.shell.spctlAssess = { _ in 
            Just((0, "", "")).setFailureType(to: Error.self).eraseToAnyPublisher()
        }

        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
        let recorder = subject.verifySecurityAssessment(of: installedXcode).record()
        try wait(for: recorder.finished, timeout: 1, description: "Finished")
    }
    
    func test_Install_FullHappyPath_Apple() throws {
        // Available xcode doesn't necessarily have build identifier
        subject.allXcodes = [
            .init(version: Version("0.0.0")!, installState: .notInstalled, selected: false, icon: nil),
            .init(version: Version("0.0.0-Beta.1")!, installState: .notInstalled, selected: false, icon: nil),
            .init(version: Version("0.0.0-Beta.2")!, installState: .notInstalled, selected: false, icon: nil),
        ]
        
        // It hasn't been downloaded
        Current.files.fileExistsAtPath = { path in
            if path == (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string {
                return false
            }
            else {
                return true
            }
        }
        Xcodes.Current.network.validateSession = {
            return Just(())
                .setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        Xcodes.Current.network.dataTask = { urlRequest in
            // Don't have a valid session
            if urlRequest.url! == URLRequest.olympusSession.url! {
                return Fail(error: AuthenticationError.invalidSession)
                    .eraseToAnyPublisher()
            }
            // It's an available release version
            else if urlRequest.url! == URLRequest.downloads.url! {
                let downloads = Downloads(resultCode: 0, resultsString: nil, downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip", fileSize: 9484444)], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return Just(
                    (
                        data: downloadsData,
                        response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    )
                )
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
            }

            return Just(
                (
                    data: Data(),
                    response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            )
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
        }
        // It downloads and updates progress
        let progress = Progress(totalUnitCount: 100)
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, AnyPublisher<(saveLocation: URL, response: URLResponse), Error>) in
            return (
                progress,
                Deferred {
                    Future { promise in
                        // Need this to run after the Promise has returned to the caller. This makes the test async, requiring waiting for an expectation.
                        DispatchQueue.main.async {
                            for i in 0...100 {
                                progress.completedUnitCount = Int64(i)
                            }
                            promise(.success((saveLocation: saveLocation,
                                              response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)))
                        }
                    }
                }
                .eraseToAnyPublisher()
            )
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            Just(
                ProcessOutput(
                    status: 0,
                    out: "",
                    err: """
                        TeamIdentifier=\(XcodeTeamIdentifier)
                        Authority=\(XcodeCertificateAuthority[0])
                        Authority=\(XcodeCertificateAuthority[1])
                        Authority=\(XcodeCertificateAuthority[2])
                        """)
            )
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
        }
        // Helper is already installed
        subject.helperInstallState = .installed

        let allXcodesRecorder = subject.$allXcodes.record()
        let installRecorder = subject.install(
            .version(AvailableXcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)),
            downloader: .urlSession
        ).record()
        try wait(for: installRecorder.finished, timeout: 1, description: "Finished")
        
        let allXcodesElements = try wait(for: allXcodesRecorder.availableElements, timeout: 1, description: "All Xcodes Elements")
        XCTAssertEqual(
            allXcodesElements.map { $0.map(\.installState) },
            [
                [XcodeInstallState.notInstalled, .notInstalled, .notInstalled], 
                [.installing(.downloading(progress: progress)), .notInstalled, .notInstalled],
                [.installing(.unarchiving), .notInstalled, .notInstalled],
                [.installing(.moving(destination: "/Applications/Xcode-0.0.0.app")), .notInstalled, .notInstalled],
                [.installing(.trashingArchive), .notInstalled, .notInstalled],
                [.installing(.checkingSecurity), .notInstalled, .notInstalled],
                [.installing(.finishing), .notInstalled, .notInstalled],
                [.installed(Path("/Applications/Xcode-0.0.0.app")!), .notInstalled, .notInstalled]
            ]
        )
    }
    
    func test_Install_FullHappyPath_XcodeReleases() throws {
        // Available xcode has build identifier
        subject.allXcodes = [
            .init(version: Version("0.0.0+ABC123")!, installState: .notInstalled, selected: false, icon: nil),
            .init(version: Version("0.0.0-Beta.1+DEF456")!, installState: .notInstalled, selected: false, icon: nil),
            .init(version: Version("0.0.0-Beta.2+GHI789")!, installState: .notInstalled, selected: false, icon: nil)
        ]
        
        // It hasn't been downloaded
        Current.files.fileExistsAtPath = { path in
            if path == (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string {
                return false
            }
            else {
                return true
            }
        }
        Xcodes.Current.network.dataTask = { urlRequest in
            // Don't have a valid session
            if urlRequest.url! == URLRequest.olympusSession.url! {
                return Fail(error: AuthenticationError.invalidSession)
                    .eraseToAnyPublisher()
            }
            // It's an available release version
            else if urlRequest.url! == URLRequest.downloads.url! {
                let downloads = Downloads(resultCode: 0, resultsString: nil, downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip", fileSize: 9494944)], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return Just(
                    (
                        data: downloadsData,
                        response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    )
                )
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
            }

            return Just(
                (
                    data: Data(),
                    response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            )
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
        }
        // It downloads and updates progress
        let progress = Progress(totalUnitCount: 100)
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, AnyPublisher<(saveLocation: URL, response: URLResponse), Error>) in
            return (
                progress,
                Deferred {
                    Future { promise in
                        // Need this to run after the Promise has returned to the caller. This makes the test async, requiring waiting for an expectation.
                        DispatchQueue.main.async {
                            for i in 0...100 {
                                progress.completedUnitCount = Int64(i)
                            }
                            promise(.success((saveLocation: saveLocation,
                                              response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)))
                        }
                    }
                }
                .eraseToAnyPublisher()
            )
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            Just(
                ProcessOutput(
                    status: 0,
                    out: "",
                    err: """
                        TeamIdentifier=\(XcodeTeamIdentifier)
                        Authority=\(XcodeCertificateAuthority[0])
                        Authority=\(XcodeCertificateAuthority[1])
                        Authority=\(XcodeCertificateAuthority[2])
                        """)
            )
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
        }
        // Helper is already installed
        subject.helperInstallState = .installed

        let allXcodesRecorder = subject.$allXcodes.record()
        let installRecorder = subject.install(
            .version(AvailableXcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)),
            downloader: .urlSession
        ).record()
        try wait(for: installRecorder.finished, timeout: 1, description: "Finished")
        
        let allXcodesElements = try wait(for: allXcodesRecorder.availableElements, timeout: 1, description: "All Xcodes Elements")
        XCTAssertEqual(
            allXcodesElements.map { $0.map(\.installState) },
            [
                [XcodeInstallState.notInstalled, .notInstalled, .notInstalled], 
                [.installing(.downloading(progress: progress)), .notInstalled, .notInstalled],
                [.installing(.unarchiving), .notInstalled, .notInstalled],
                [.installing(.moving(destination: "/Applications/Xcode-0.0.0.app")), .notInstalled, .notInstalled],
                [.installing(.trashingArchive), .notInstalled, .notInstalled],
                [.installing(.checkingSecurity), .notInstalled, .notInstalled],
                [.installing(.finishing), .notInstalled, .notInstalled],
                [.installed(Path("/Applications/Xcode-0.0.0.app")!), .notInstalled, .notInstalled]
            ]
        )
    }

    func test_Install_NotEnoughFreeSpace() throws {
        Current.shell.unxip = { _ in
            Fail(error: ProcessExecutionError(
                    process: Process(),
                    standardOutput: "xip: signing certificate was \"Development Update\" (validation not attempted)", 
                    standardError: "xip: error: The archive “Xcode-12.4.0-Release.Candidate+12D4e.xip” can’t be expanded because the selected volume doesn’t have enough free space."
            ))
            .eraseToAnyPublisher()
        }
        let archiveURL = URL(fileURLWithPath: "/Users/user/Library/Application Support/Xcode-0.0.0.xip")
        
        let recorder = subject.unarchiveAndMoveXIP(
            availableXcode: AvailableXcode(
                version: Version("0.0.0")!,
                url: URL(string: "https://developer.apple.com")!, 
                filename: "Xcode-0.0.0.xip", 
                releaseDate: nil
            ),
            at: archiveURL,
            to: URL(string: "/Applications/Xcode-0.0.0.app")!
        ).record()
        
        let completion = try wait(for: recorder.completion, timeout: 1, description: "Completion")

        if case let .failure(error as InstallationError) = completion { 
            XCTAssertEqual(
                error,
                InstallationError.notEnoughFreeSpaceToExpandArchive(archivePath: Path(url: archiveURL)!, 
                                                                    version: Version("0.0.0")!)
            )
        }
        else {
            XCTFail() 
        }        
    }
}
