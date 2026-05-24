import XCTest
@preconcurrency import Path
import Version
import os
@testable import XcodesKit

final class XcodesKitTests: XCTestCase {
    func testOneShotContinuationReturnsResultCompletedBeforeContinuationIsSet() async throws {
        let oneShot = OneShotContinuation<String>()

        oneShot.resume(with: .success("ready"))
        let value = try await withCheckedThrowingContinuation { continuation in
            oneShot.setContinuation(continuation)
        }

        XCTAssertEqual(value, "ready")
    }

    func testOneShotContinuationIgnoresRepeatedResume() async throws {
        let oneShot = OneShotContinuation<String>()

        oneShot.resume(with: .success("first"))
        oneShot.resume(with: .success("second"))
        let value = try await withCheckedThrowingContinuation { continuation in
            oneShot.setContinuation(continuation)
        }

        XCTAssertEqual(value, "first")
    }

    func testXcodeInstallRetryServiceRetriesDamagedArchiveOnce() async throws {
        let damagedURL = URL(fileURLWithPath: "/tmp/Xcode.xip")
        let attempts = RetryRecorder<Int>()
        let failures = RetryRecorder<String>()
        let retries = RetryRecorder<URL>()
        let removals = URLListRecorder()
        let installedXcode = InstalledXcode(
            path: try XCTUnwrap(Path("/Applications/Xcode.app")),
            version: try XCTUnwrap(Version("15.0.0"))
        )
        let service = XcodeInstallRetryService(
            damagedArchiveURL: { error in
                guard case XcodeInstallRetryTestError.damagedArchive(let url) = error else { return nil }
                return url
            },
            removeDamagedArchive: { url in
                removals.record(url)
            }
        )

        let result = try await service.install(
            attempt: { _ in
                let attempt = await attempts.record(1)
                if attempt == 1 {
                    throw XcodeInstallRetryTestError.damagedArchive(damagedURL)
                }
                return installedXcode
            },
            onAttemptFailed: { error in
                await failures.record(String(describing: error))
            },
            onRetryDamagedArchive: { _, url in
                await retries.record(url)
            }
        )

        let attemptCount = await attempts.count
        let failureCount = await failures.count
        let retriedURLs = await retries.values

        XCTAssertEqual(result, installedXcode)
        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(failureCount, 1)
        XCTAssertEqual(retriedURLs, [damagedURL])
        XCTAssertEqual(removals.paths, [damagedURL.path])
    }

    func testXcodeInstallRetryServiceDoesNotRetryWhenDisabled() async throws {
        let damagedURL = URL(fileURLWithPath: "/tmp/Xcode.xip")
        let attempts = RetryRecorder<Int>()
        let removals = URLListRecorder()
        let service = XcodeInstallRetryService(
            damagedArchiveURL: { error in
                guard case XcodeInstallRetryTestError.damagedArchive(let url) = error else { return nil }
                return url
            },
            removeDamagedArchive: { url in
                removals.record(url)
            }
        )

        do {
            _ = try await service.install(
                shouldRetryAfterDamagedArchive: false,
                attempt: { _ in
                    await attempts.record(1)
                    throw XcodeInstallRetryTestError.damagedArchive(damagedURL)
                }
            )
            XCTFail("Expected damaged archive error")
        } catch XcodeInstallRetryTestError.damagedArchive(let url) {
            XCTAssertEqual(url, damagedURL)
        }

        let attemptCount = await attempts.count

        XCTAssertEqual(attemptCount, 1)
        XCTAssertEqual(removals.paths, [])
    }

    func testXcodeSignatureVerifierParsesCertificateInfo() {
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

        let signature = XcodeSignatureVerifier().parse(sampleRawInfo)

        XCTAssertEqual(signature.authority, XcodeSignatureVerifier.expectedCertificateAuthority)
        XCTAssertEqual(signature.teamIdentifier, XcodeSignatureVerifier.expectedTeamIdentifier)
        XCTAssertEqual(signature.bundleIdentifier, "com.apple.dt.Xcode")
    }

    func testXcodeSignatureVerifierValidatesExpectedAppleSignature() {
        let signature = XcodeSignature(
            authority: XcodeSignatureVerifier.expectedCertificateAuthority,
            teamIdentifier: XcodeSignatureVerifier.expectedTeamIdentifier,
            bundleIdentifier: "com.apple.dt.Xcode"
        )

        XCTAssertTrue(XcodeSignatureVerifier().isValid(signature))
    }

    func testXcodeSignatureVerifierRejectsUnexpectedAppleSignature() {
        let signature = XcodeSignature(
            authority: XcodeSignatureVerifier.expectedCertificateAuthority,
            teamIdentifier: "NOTAPPLE",
            bundleIdentifier: "com.apple.dt.Xcode"
        )

        XCTAssertFalse(XcodeSignatureVerifier().isValid(signature))
    }

    func testXcodeValidationServiceMapsSecurityAssessmentProcessOutput() async throws {
        let xcode = InstalledXcode(
            path: try XCTUnwrap(Path("/Applications/Xcode.app")),
            version: try XCTUnwrap(Version("15.0.0"))
        )
        let service = XcodeValidationService(
            assessSecurity: { _ in
                throw ProcessExecutionError(
                    process: Process(),
                    terminationStatus: 1,
                    standardOutput: "assessment stdout",
                    standardError: "assessment stderr"
                )
            },
            verifyCodesign: { _ in (0, "", "") }
        )

        do {
            try await service.verifySecurityAssessment(of: xcode)
            XCTFail("Expected validation to throw")
        } catch let error as XcodeValidationError {
            XCTAssertEqual(error, .failedSecurityAssessment(xcode: xcode, output: "assessment stdout\nassessment stderr"))
        }
    }

    func testXcodeValidationServiceMapsCodesignProcessOutput() async throws {
        let service = XcodeValidationService(
            assessSecurity: { _ in (0, "", "") },
            verifyCodesign: { _ in
                throw ProcessExecutionError(
                    process: Process(),
                    terminationStatus: 1,
                    standardOutput: "",
                    standardError: "codesign stderr"
                )
            }
        )

        do {
            try await service.verifySigningCertificate(of: URL(fileURLWithPath: "/Applications/Xcode.app"))
            XCTFail("Expected validation to throw")
        } catch let error as XcodeValidationError {
            XCTAssertEqual(error, .codesignVerifyFailed(output: "codesign stderr"))
        }
    }

    func testXcodeValidationServiceRejectsUnexpectedSigningIdentity() async throws {
        let service = XcodeValidationService(
            assessSecurity: { _ in (0, "", "") },
            verifyCodesign: { _ in
                (0, "", """
                Identifier=com.apple.dt.Xcode
                Authority=Software Signing
                Authority=Apple Code Signing Certification Authority
                Authority=Apple Root CA
                TeamIdentifier=NOTAPPLE
                """)
            }
        )

        do {
            try await service.verifySigningCertificate(of: URL(fileURLWithPath: "/Applications/Xcode.app"))
            XCTFail("Expected validation to throw")
        } catch let error as XcodeValidationError {
            XCTAssertEqual(error, .unexpectedCodeSigningIdentity(
                identifier: "NOTAPPLE",
                certificateAuthority: XcodeSignatureVerifier.expectedCertificateAuthority
            ))
        }
    }

    func testXcodeArchiveInstallServiceInstallsXIPAndValidatesXcode() async throws {
        let archiveURL = URL(fileURLWithPath: "/tmp/Xcode.xip")
        let destinationDirectory = try XCTUnwrap(Path("/Applications"))
        let destinationPath = try XCTUnwrap(Path("/Applications/Xcode-15.0.0.app"))
        let recorder = PathOperationRecorder()
        let stepRecorder = XcodeArchiveInstallStepRecorder()
        let xcode = AvailableXcode(
            version: try XCTUnwrap(Version("15.0.0")),
            url: archiveURL,
            filename: "Xcode.xip",
            releaseDate: nil
        )

        let service = XcodeArchiveInstallService(
            destinationDirectory: destinationDirectory,
            unarchiveService: XcodeUnarchiveService(
                unarchive: { url in
                    XCTAssertEqual(url, archiveURL)
                    recorder.record("unarchive")
                },
                fileExists: { path in
                    path == "/tmp/Xcode.app" || path == destinationPath.string
                },
                moveItem: { source, destination in
                    XCTAssertEqual(source.path, "/tmp/Xcode.app")
                    XCTAssertEqual(destination.path, destinationPath.url.path)
                    recorder.record("move")
                },
                removeItem: { _ in }
            ),
            validationService: XcodeValidationService(
                assessSecurity: { url in
                    XCTAssertEqual(url.path, destinationPath.url.path)
                    return (0, "", "")
                },
                verifyCodesign: { url in
                    XCTAssertEqual(url.path, destinationPath.url.path)
                    return (0, "", """
                    Identifier=com.apple.dt.Xcode
                    Authority=Software Signing
                    Authority=Apple Code Signing Certification Authority
                    Authority=Apple Root CA
                    TeamIdentifier=59GAB85EFG
                    """)
                }
            ),
            fileExists: { path in path == destinationPath.string },
            makeInstalledXcode: { path in
                XCTAssertEqual(path, destinationPath)
                return InstalledXcode(path: path, version: Version("15.0.0")!)
            }
        )

        let installedXcode = try await service.installArchivedXcode(
            xcode,
            at: archiveURL,
            cleanArchive: { url in
                XCTAssertEqual(url, archiveURL)
                recorder.record("clean")
            },
            stepChanged: { step in
                await stepRecorder.record(step)
            }
        )

        XCTAssertEqual(installedXcode.path, destinationPath)
        XCTAssertEqual(recorder.operations, ["unarchive", "move", "clean"])
        let steps = await stepRecorder.recordedSteps()
        XCTAssertEqual(steps, [
            .unarchive(.unarchiving),
            .unarchive(.moving(destination: destinationPath.url.path)),
            .cleaningArchive(archiveName: "Xcode.xip"),
            .checkingSecurity
        ])
    }

    func testXcodeArchiveInstallServiceRejectsUnsupportedArchives() async throws {
        let service = XcodeArchiveInstallService(
            destinationDirectory: try XCTUnwrap(Path("/Applications")),
            unarchiveService: XcodeUnarchiveService(
                unarchive: { _ in XCTFail("Unsupported archives should not be unarchived") },
                fileExists: { _ in false },
                moveItem: { _, _ in },
                removeItem: { _ in }
            ),
            validationService: XcodeValidationService(
                assessSecurity: { _ in (0, "", "") },
                verifyCodesign: { _ in (0, "", "") }
            ),
            fileExists: { _ in false },
            makeInstalledXcode: { _ in nil }
        )
        let xcode = AvailableXcode(
            version: try XCTUnwrap(Version("15.0.0")),
            url: URL(fileURLWithPath: "/tmp/Xcode.dmg"),
            filename: "Xcode.dmg",
            releaseDate: nil
        )

        do {
            _ = try await service.installArchivedXcode(
                xcode,
                at: URL(fileURLWithPath: "/tmp/Xcode.dmg"),
                cleanArchive: { _ in XCTFail("Unsupported archives should not be cleaned") }
            )
            XCTFail("Expected unsupported archive to throw")
        } catch let error as XcodeArchiveInstallError {
            XCTAssertEqual(error, .unsupportedFileFormat(extension: "dmg"))
        }
    }

    func testXcodeUpdatePolicyUsesFiveHourFreshnessWindow() {
        let now = Date(timeIntervalSince1970: 10_000)
        let policy = XcodeUpdatePolicy(now: { now })
        let cachedXcodes = [
            AvailableXcode(
                version: Version("15.0.0")!,
                url: URL(fileURLWithPath: "/tmp/Xcode.xip"),
                filename: "Xcode.xip",
                releaseDate: nil
            )
        ]

        XCTAssertFalse(policy.shouldUpdate(
            cachedXcodes: cachedXcodes,
            lastUpdated: now.addingTimeInterval(-XcodeUpdatePolicy.defaultMaximumCacheAge + 1)
        ))
        XCTAssertTrue(policy.shouldUpdate(
            cachedXcodes: cachedXcodes,
            lastUpdated: now.addingTimeInterval(-XcodeUpdatePolicy.defaultMaximumCacheAge - 1)
        ))
    }

    func testXcodeUpdatePolicyUpdatesWhenCacheIsEmptyOrMissingDate() {
        let policy = XcodeUpdatePolicy(now: { Date(timeIntervalSince1970: 10_000) })
        let cachedXcodes = [
            AvailableXcode(
                version: Version("15.0.0")!,
                url: URL(fileURLWithPath: "/tmp/Xcode.xip"),
                filename: "Xcode.xip",
                releaseDate: nil
            )
        ]

        XCTAssertTrue(policy.shouldUpdate(cachedXcodes: [], lastUpdated: Date()))
        XCTAssertTrue(policy.shouldUpdate(cachedXcodes: cachedXcodes, lastUpdated: nil))
    }

    func testXcodePostInstallServiceRunsFirstLaunchAndTouchesInstallCheck() async throws {
        let xcode = InstalledXcode(
            path: try XCTUnwrap(Path("/Applications/Xcode.app")),
            version: try XCTUnwrap(Version("15.0.0+15A1"))
        )
        let recorder = XcodePostInstallRecorder()
        let service = XcodePostInstallService(
            runFirstLaunch: { receivedXcode in
                XCTAssertEqual(receivedXcode, xcode)
                await recorder.recordFirstLaunch()
            },
            getUserCacheDirectory: { (0, "/tmp/cache/", "") },
            getMacOSBuildVersion: { (0, "23A344", "") },
            getXcodeBuildVersion: { receivedXcode in
                XCTAssertEqual(receivedXcode, xcode)
                return (0, "15A1", "")
            },
            touchInstallCheck: { cacheDirectory, macOSBuildVersion, toolsVersion in
                await recorder.recordInstallCheck(
                    cacheDirectory: cacheDirectory,
                    macOSBuildVersion: macOSBuildVersion,
                    toolsVersion: toolsVersion
                )
                return (0, "", "")
            }
        )

        try await service.installComponents(for: xcode)

        let didRunFirstLaunch = await recorder.didRunFirstLaunch
        let touchedInstallCheck = await recorder.touchedInstallCheck
        XCTAssertTrue(didRunFirstLaunch)
        XCTAssertEqual(touchedInstallCheck?.cacheDirectory, "/tmp/cache/")
        XCTAssertEqual(touchedInstallCheck?.macOSBuildVersion, "23A344")
        XCTAssertEqual(touchedInstallCheck?.toolsVersion, "15A1")
    }

    func testXcodePostInstallPreparationServiceEnablesDeveloperModeAndApprovesLicense() async throws {
        let xcode = InstalledXcode(
            path: try XCTUnwrap(Path("/Applications/Xcode.app")),
            version: try XCTUnwrap(Version("15.0.0"))
        )
        let recorder = XcodePostInstallPreparationRecorder()
        let service = XcodePostInstallPreparationService(
            enableDeveloperTools: {
                await recorder.record(.enableDeveloperTools)
            },
            addStaffToDevelopersGroup: {
                await recorder.record(.addStaffToDevelopersGroup)
            },
            acceptLicense: { receivedXcode in
                XCTAssertEqual(receivedXcode, xcode)
                await recorder.record(.acceptLicense)
            }
        )

        try await service.enableDeveloperMode()
        try await service.approveLicense(for: xcode)

        let events = await recorder.events
        XCTAssertEqual(events, [
            .enableDeveloperTools,
            .addStaffToDevelopersGroup,
            .acceptLicense
        ])
    }

    func testXcodeUninstallServiceMovesXcodeToTrash() throws {
        let xcode = InstalledXcode(
            path: try XCTUnwrap(Path("/Applications/Xcode.app")),
            version: try XCTUnwrap(Version("15.0.0"))
        )
        let recorder = URLRecorder()
        let service = XcodeUninstallService(
            removeItem: { _ in XCTFail("Remove should not be called") },
            trashItem: { url in
                recorder.record(url)
                return URL(fileURLWithPath: "/Users/test/.Trash/Xcode.app")
            }
        )

        let result = try service.uninstall(xcode, emptyTrash: false)

        XCTAssertEqual(recorder.url, xcode.path.url)
        XCTAssertEqual(result.xcode, xcode)
        XCTAssertEqual(result.trashURL?.path, "/Users/test/.Trash/Xcode.app")
        XCTAssertFalse(result.didDeleteImmediately)
    }

    func testXcodeUninstallServiceDeletesXcodeImmediately() throws {
        let xcode = InstalledXcode(
            path: try XCTUnwrap(Path("/Applications/Xcode.app")),
            version: try XCTUnwrap(Version("15.0.0"))
        )
        let recorder = URLRecorder()
        let service = XcodeUninstallService(
            removeItem: { url in recorder.record(url) },
            trashItem: { _ in
                XCTFail("Trash should not be called")
                return URL(fileURLWithPath: "/Users/test/.Trash/Xcode.app")
            }
        )

        let result = try service.uninstall(xcode, emptyTrash: true)

        XCTAssertEqual(recorder.url, xcode.path.url)
        XCTAssertEqual(result.xcode, xcode)
        XCTAssertNil(result.trashURL)
        XCTAssertTrue(result.didDeleteImmediately)
    }

    func testXcodeSelectionFilesystemServiceCreatesSymlink() throws {
        let recorder = PathOperationRecorder()
        let service = XcodeSelectionFilesystemService(
            fileExists: { _ in false },
            attributesOfItem: { _ in [:] },
            removeItem: { _ in XCTFail("Remove should not be called") },
            createSymbolicLink: { destination, source in
                recorder.record("link:\(destination)->\(source)")
            },
            installedXcode: { _ in nil }
        )

        let result = try service.createSymbolicLink(
            to: try XCTUnwrap(Path("/Applications/Xcode-15.0.app")),
            in: try XCTUnwrap(Path("/Applications"))
        )

        XCTAssertEqual(result.destinationPath.string, "/Applications/Xcode.app")
        XCTAssertFalse(result.replacedExistingSymlink)
        XCTAssertEqual(recorder.operations, ["link:/Applications/Xcode.app->/Applications/Xcode-15.0.app"])
    }

    func testXcodeSelectionFilesystemServiceReplacesExistingSymlink() throws {
        let recorder = PathOperationRecorder()
        let service = XcodeSelectionFilesystemService(
            fileExists: { _ in true },
            attributesOfItem: { _ in [.type: FileAttributeType.typeSymbolicLink] },
            removeItem: { path in recorder.record("remove:\(path)") },
            createSymbolicLink: { destination, source in
                recorder.record("link:\(destination)->\(source)")
            },
            installedXcode: { _ in nil }
        )

        let result = try service.createSymbolicLink(
            to: try XCTUnwrap(Path("/Applications/Xcode-15.0.app")),
            in: try XCTUnwrap(Path("/Applications")),
            isBeta: true
        )

        XCTAssertEqual(result.destinationPath.string, "/Applications/Xcode-Beta.app")
        XCTAssertTrue(result.replacedExistingSymlink)
        XCTAssertEqual(recorder.operations, [
            "remove:/Applications/Xcode-Beta.app",
            "link:/Applications/Xcode-Beta.app->/Applications/Xcode-15.0.app"
        ])
    }

    func testXcodeSelectionFilesystemServiceRejectsReplacingRealAppBundleWithSymlink() throws {
        let service = XcodeSelectionFilesystemService(
            fileExists: { _ in true },
            attributesOfItem: { _ in [.type: FileAttributeType.typeDirectory] },
            removeItem: { _ in XCTFail("Remove should not be called") },
            createSymbolicLink: { _, _ in XCTFail("Link should not be called") },
            installedXcode: { _ in nil }
        )
        let expectedPath = try XCTUnwrap(Path("/Applications/Xcode.app"))

        XCTAssertThrowsError(try service.createSymbolicLink(
            to: try XCTUnwrap(Path("/Applications/Xcode-15.0.app")),
            in: try XCTUnwrap(Path("/Applications"))
        )) { error in
            XCTAssertEqual(
                error as? XcodeSelectionFilesystemError,
                .destinationExistsAndIsNotSymlink(expectedPath)
            )
        }
    }

    func testXcodeSelectionFilesystemServiceRenamesExistingXcodeAppBeforeSelectionRename() throws {
        let recorder = PathOperationRecorder()
        let destinationPath = try XCTUnwrap(Path("/Applications/Xcode.app"))
        let selectedPath = try XCTUnwrap(Path("/Applications/Xcode-15.1.app"))
        let service = XcodeSelectionFilesystemService(
            fileExists: { $0 == destinationPath.string },
            installedXcode: { path in
                XCTAssertEqual(path, destinationPath)
                return InstalledXcode(
                    path: path,
                    version: try! XCTUnwrap(Version("14.3.1"))
                )
            },
            rename: { path, newName in
                recorder.record("rename:\(path.string)->\(newName)")
                return path.parent/newName
            }
        )

        let renamedPath = try service.renameForSelection(
            installedXcodePath: selectedPath,
            in: try XCTUnwrap(Path("/Applications"))
        )

        XCTAssertEqual(renamedPath.string, "/Applications/Xcode.app")
        XCTAssertEqual(recorder.operations, [
            "rename:/Applications/Xcode.app->Xcode-14.3.1.app",
            "rename:/Applications/Xcode-15.1.app->Xcode.app"
        ])
    }

    func testXcodeSelectionServiceSelectsInstalledVersion() throws {
        let first = InstalledXcode(path: try XCTUnwrap(Path("/Applications/Xcode-15.0.app")), version: Version("15.0.0")!)
        let second = InstalledXcode(path: try XCTUnwrap(Path("/Applications/Xcode-15.1.app")), version: Version("15.1.0")!)
        let service = XcodeSelectionService(versionFile: XcodeVersionFileService(fileExists: { _ in false }, contentsAtPath: { _ in nil }))

        let request = service.request(
            pathOrVersion: "15.1",
            installedXcodes: [first, second],
            selectedXcodePath: "\(first.path.string)/Contents/Developer"
        )

        XCTAssertEqual(request, .selectInstalledXcode(second))
    }

    func testXcodeSelectionServiceDetectsAlreadySelectedVersion() throws {
        let xcode = InstalledXcode(path: try XCTUnwrap(Path("/Applications/Xcode-15.0.app")), version: Version("15.0.0")!)
        let service = XcodeSelectionService(versionFile: XcodeVersionFileService(fileExists: { _ in false }, contentsAtPath: { _ in nil }))

        let request = service.request(
            pathOrVersion: "15.0",
            installedXcodes: [xcode],
            selectedXcodePath: "\(xcode.path.string)/Contents/Developer"
        )

        XCTAssertEqual(request, .alreadySelectedVersion(Version("15.0.0")!))
    }

    func testXcodeSelectionServiceUsesVersionFileWhenNoArgumentIsProvided() throws {
        let xcode = InstalledXcode(path: try XCTUnwrap(Path("/Applications/Xcode-15.0.app")), version: Version("15.0.0")!)
        let service = XcodeSelectionService(versionFile: XcodeVersionFileService(
            fileExists: { $0 == "/project/.xcode-version" },
            contentsAtPath: { _ in Data("15.0\n".utf8) }
        ))

        let request = service.request(
            pathOrVersion: "",
            installedXcodes: [xcode],
            selectedXcodePath: "",
            versionFileDirectory: try XCTUnwrap(Path("/project"))
        )

        XCTAssertEqual(request, .selectInstalledXcode(xcode))
    }

    func testXcodeSelectionServiceFallsBackToPathSelection() {
        let service = XcodeSelectionService(versionFile: XcodeVersionFileService(fileExists: { _ in false }, contentsAtPath: { _ in nil }))

        let request = service.request(
            pathOrVersion: " /Applications/Xcode.app\n",
            installedXcodes: [],
            selectedXcodePath: ""
        )

        XCTAssertEqual(request, .selectPath("/Applications/Xcode.app"))
    }

    func testXcodeSelectionServiceChoosesInstalledXcodeBySelectionNumber() throws {
        let first = InstalledXcode(path: try XCTUnwrap(Path("/Applications/Xcode-15.0.app")), version: Version("15.0.0")!)
        let second = InstalledXcode(path: try XCTUnwrap(Path("/Applications/Xcode-15.1.app")), version: Version("15.1.0")!)
        let service = XcodeSelectionService(versionFile: XcodeVersionFileService(fileExists: { _ in false }, contentsAtPath: { _ in nil }))

        let selected = try service.installedXcode(fromSelection: "2", installedXcodes: [second, first])

        XCTAssertEqual(selected, second)
    }

    func testXcodeSelectionServiceRejectsInvalidSelectionNumber() throws {
        let xcode = InstalledXcode(path: try XCTUnwrap(Path("/Applications/Xcode-15.0.app")), version: Version("15.0.0")!)
        let service = XcodeSelectionService(versionFile: XcodeVersionFileService(fileExists: { _ in false }, contentsAtPath: { _ in nil }))

        XCTAssertThrowsError(try service.installedXcode(fromSelection: "3", installedXcodes: [xcode])) { error in
            XCTAssertEqual(error as? XcodeSelectionError, .invalidIndex(min: 1, max: 1, given: "3"))
        }
    }

    func testXcodeInstallResolutionServiceSelectsLatestReleaseVersion() throws {
        let release = AvailableXcode(version: Version("15.0.0")!, url: URL(fileURLWithPath: "/Xcode-15.xip"), filename: "Xcode-15.xip", releaseDate: nil)
        let prerelease = AvailableXcode(version: Version("16.0.0-beta.1")!, url: URL(fileURLWithPath: "/Xcode-16-beta.xip"), filename: "Xcode-16-beta.xip", releaseDate: Date())
        let service = XcodeInstallResolutionService(versionFile: XcodeVersionFileService(fileExists: { _ in false }, contentsAtPath: { _ in nil }))

        let resolution = try service.resolve(
            .latest,
            availableXcodes: [prerelease, release],
            installedXcodes: [],
            willInstall: true
        )

        XCTAssertEqual(resolution, .download(version: release.version, resolvedXcode: release))
    }

    func testXcodeInstallResolutionServiceSelectsLatestPrereleaseByReleaseDate() throws {
        let older = AvailableXcode(version: Version("16.0.0-beta.2")!, url: URL(fileURLWithPath: "/older.xip"), filename: "older.xip", releaseDate: Date(timeIntervalSince1970: 1))
        let newer = AvailableXcode(version: Version("16.0.0-beta.1")!, url: URL(fileURLWithPath: "/newer.xip"), filename: "newer.xip", releaseDate: Date(timeIntervalSince1970: 2))
        let service = XcodeInstallResolutionService(versionFile: XcodeVersionFileService(fileExists: { _ in false }, contentsAtPath: { _ in nil }))

        let resolution = try service.resolve(
            .latestPrerelease,
            availableXcodes: [newer, older],
            installedXcodes: [],
            willInstall: true
        )

        XCTAssertEqual(resolution, .download(version: newer.version, resolvedXcode: newer))
    }

    func testXcodeInstallResolutionServiceRejectsLatestPrereleaseWithoutReleaseDate() throws {
        let prerelease = AvailableXcode(version: Version("16.0.0-beta.1")!, url: URL(fileURLWithPath: "/beta.xip"), filename: "beta.xip", releaseDate: nil)
        let service = XcodeInstallResolutionService(versionFile: XcodeVersionFileService(fileExists: { _ in false }, contentsAtPath: { _ in nil }))

        XCTAssertThrowsError(try service.resolve(
            .latestPrerelease,
            availableXcodes: [prerelease],
            installedXcodes: [],
            willInstall: true
        )) { error in
            XCTAssertEqual(error as? XcodeInstallResolutionError, .noPrereleaseVersionAvailable)
        }
    }

    func testXcodeInstallResolutionServiceRejectsInstalledVersionWhenInstalling() throws {
        let installed = InstalledXcode(path: try XCTUnwrap(Path("/Applications/Xcode-15.0.app")), version: Version("15.0.0")!)
        let service = XcodeInstallResolutionService(versionFile: XcodeVersionFileService(fileExists: { _ in false }, contentsAtPath: { _ in nil }))

        XCTAssertThrowsError(try service.resolve(
            .version("15.0"),
            availableXcodes: [],
            installedXcodes: [installed],
            willInstall: true
        )) { error in
            XCTAssertEqual(error as? XcodeInstallResolutionError, .versionAlreadyInstalled(installed))
        }
    }

    func testXcodeInstallResolutionServiceRejectsInstalledAvailableXcodeWhenInstalling() throws {
        let available = AvailableXcode(version: Version("15.0.0")!, url: URL(fileURLWithPath: "/Xcode-15.xip"), filename: "Xcode-15.xip", releaseDate: nil)
        let installed = InstalledXcode(path: try XCTUnwrap(Path("/Applications/Xcode-15.0.app")), version: Version("15.0.0")!)
        let service = XcodeInstallResolutionService(versionFile: XcodeVersionFileService(fileExists: { _ in false }, contentsAtPath: { _ in nil }))

        XCTAssertThrowsError(try service.resolve(
            .availableXcode(available),
            availableXcodes: [],
            installedXcodes: [installed],
            willInstall: true
        )) { error in
            XCTAssertEqual(error as? XcodeInstallResolutionError, .versionAlreadyInstalled(installed))
        }
    }

    func testXcodeInstallResolutionServiceResolvesAvailableXcodeForInstall() throws {
        let available = AvailableXcode(version: Version("15.0.0")!, url: URL(fileURLWithPath: "/Xcode-15.xip"), filename: "Xcode-15.xip", releaseDate: nil)
        let service = XcodeInstallResolutionService(versionFile: XcodeVersionFileService(fileExists: { _ in false }, contentsAtPath: { _ in nil }))

        let resolution = try service.resolve(
            .availableXcode(available),
            availableXcodes: [],
            installedXcodes: [],
            willInstall: true
        )

        XCTAssertEqual(resolution, .download(version: available.version, resolvedXcode: available))
    }

    func testXcodeInstallResolutionServiceAllowsInstalledVersionWhenOnlyDownloading() throws {
        let installed = InstalledXcode(path: try XCTUnwrap(Path("/Applications/Xcode-15.0.app")), version: Version("15.0.0")!)
        let service = XcodeInstallResolutionService(versionFile: XcodeVersionFileService(fileExists: { _ in false }, contentsAtPath: { _ in nil }))

        let resolution = try service.resolve(
            .version("15.0"),
            availableXcodes: [],
            installedXcodes: [installed],
            willInstall: false
        )

        XCTAssertEqual(resolution, .download(version: Version("15.0.0")!, resolvedXcode: nil))
    }

    func testXcodeInstallResolutionServiceUsesVersionFileForPathArchive() throws {
        let archivePath = try XCTUnwrap(Path("/tmp/Xcode.xip"))
        let service = XcodeInstallResolutionService(versionFile: XcodeVersionFileService(
            fileExists: { $0 == "/project/.xcode-version" },
            contentsAtPath: { _ in Data("15.1\n".utf8) }
        ))

        let resolution = try service.resolve(
            .path(versionString: "", path: archivePath),
            availableXcodes: [],
            installedXcodes: [],
            willInstall: true,
            versionFileDirectory: try XCTUnwrap(Path("/project"))
        )

        XCTAssertEqual(
            resolution,
            .localArchive(
                AvailableXcode(version: Version("15.1.0")!, url: archivePath.url, filename: "Xcode.xip", releaseDate: nil),
                archivePath.url
            )
        )
    }

    func testArchiveCancellationCleanupServiceRemovesXcodeArchiveAndAria2Metadata() throws {
        let recorder = URLListRecorder()
        let xcode = AvailableXcode(
            version: try XCTUnwrap(Version("15.0.0")),
            url: try XCTUnwrap(URL(string: "https://example.com/Xcode_15.xip")),
            filename: "Xcode_15.xip",
            releaseDate: nil
        )
        let service = ArchiveCancellationCleanupService { url in
            recorder.record(url)
        }

        service.cleanupXcodeArchive(
            for: xcode,
            applicationSupportPath: try XCTUnwrap(Path("/tmp/xcodes"))
        )

        XCTAssertEqual(recorder.paths, [
            "/tmp/xcodes/Xcode-15.0.0.xip",
            "/tmp/xcodes/Xcode-15.0.0.xip.aria2"
        ])
    }

    func testArchiveCancellationCleanupServiceRemovesRuntimeArchiveAndAria2Metadata() throws {
        let recorder = URLListRecorder()
        let runtime = downloadableRuntime(source: "https://example.com/iOS_16_Runtime.dmg")
        let service = ArchiveCancellationCleanupService { url in
            recorder.record(url)
        }

        service.cleanupRuntimeArchive(
            for: runtime,
            destinationDirectory: try XCTUnwrap(Path("/tmp/xcodes"))
        )

        XCTAssertEqual(recorder.paths, [
            "/tmp/xcodes/iOS_16_Runtime.dmg",
            "/tmp/xcodes/iOS_16_Runtime.dmg.aria2"
        ])
    }

    func testAttemptResumableTaskRetriesWithResumeData() async throws {
        let retryResumeData = Data("resume".utf8)
        let recorder = RetryRecorder<Data?>()

        let result = try await attemptResumableTask(delayBeforeRetry: .zero) { resumeData in
            let attempts = await recorder.record(resumeData)

            if attempts == 1 {
                throw NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorNetworkConnectionLost,
                    userInfo: [NSURLSessionDownloadTaskResumeData: retryResumeData]
                )
            }

            return "finished"
        }

        XCTAssertEqual(result, "finished")
        let receivedResumeData = await recorder.values
        XCTAssertEqual(receivedResumeData, [nil, retryResumeData])
    }

    func testAttemptResumableTaskDoesNotRetryRejectedError() async throws {
        let resumeData = Data("resume".utf8)
        let recorder = RetryRecorder<Data?>()
        let expectedError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorUserCancelledAuthentication,
            userInfo: [NSURLSessionDownloadTaskResumeData: resumeData]
        )

        do {
            _ = try await attemptResumableTask(
                delayBeforeRetry: .zero,
                shouldRetry: { _ in false },
                { _ in
                    await recorder.record(nil)
                    throw expectedError
                }
            ) as String
            XCTFail("Expected rejected retry to throw")
        } catch {
            let attempts = await recorder.count
            XCTAssertEqual(attempts, 1)
            XCTAssertEqual(error as NSError, expectedError)
        }
    }

    func testAttemptRetryableTaskRetriesApprovedError() async throws {
        let recorder = RetryRecorder<Void>()

        let result = try await attemptRetryableTask(delayBeforeRetry: .zero) {
            let attempts = await recorder.record(())

            if attempts == 1 {
                throw URLError(.networkConnectionLost)
            }

            return "finished"
        }

        XCTAssertEqual(result, "finished")
        let attempts = await recorder.count
        XCTAssertEqual(attempts, 2)
    }

    func testArchiveDownloadServiceURLSessionUsesPersistedResumeData() async throws {
        let persistedResumeData = Data("persisted".utf8)
        let recorder = DownloadRecorder()
        let resumeDataPath = try XCTUnwrap(Path("/tmp/Xcode-15.resumedata"))
        let destination = try XCTUnwrap(Path("/tmp/Xcode-15.xip"))
        let downloadURL = try XCTUnwrap(URL(string: "https://example.com/Xcode.xip"))
        let service = ArchiveDownloadService(
            aria2Download: { _, _, _, _ in
                XCTFail("Aria2 should not be used")
                return AsyncThrowingStream { $0.finish() }
            },
            urlSessionDownload: { url, destination, resumeData in
                recorder.recordURLSession(url: url, destination: destination, resumeData: resumeData)
                return (
                    Progress(totalUnitCount: 10),
                    Task {
                        (
                            saveLocation: destination,
                            response: try XCTUnwrap(URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
                        )
                    }
                )
            },
            contentsAtPath: { path in
                path == resumeDataPath.string ? persistedResumeData : nil
            },
            createFile: { _, _ in XCTFail("Resume data should not be persisted on success") },
            removeItem: { url in recorder.recordRemovedURL(url) }
        )

        let url = try await service.downloadWithURLSession(
            url: downloadURL,
            destination: destination,
            resumeDataPath: resumeDataPath,
            progressChanged: { recorder.recordProgress($0) }
        )

        XCTAssertEqual(url, destination.url)
        XCTAssertEqual(recorder.urlSessionResumeData, persistedResumeData)
        XCTAssertEqual(recorder.removedURLs.map(\.path), [resumeDataPath.string])
        XCTAssertEqual(recorder.progressCount, 1)
    }

    func testArchiveDownloadServiceURLSessionPersistsResumeDataOnFailure() async throws {
        let failedResumeData = Data("failed".utf8)
        let recorder = DownloadRecorder()
        let resumeDataPath = try XCTUnwrap(Path("/tmp/Xcode-15.resumedata"))
        let expectedError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: [NSURLSessionDownloadTaskResumeData: failedResumeData]
        )
        let service = ArchiveDownloadService(
            aria2Download: { _, _, _, _ in
                XCTFail("Aria2 should not be used")
                return AsyncThrowingStream { $0.finish() }
            },
            urlSessionDownload: { _, _, _ in
                (
                    Progress(totalUnitCount: 10),
                    Task {
                        throw expectedError
                    }
                )
            },
            contentsAtPath: { _ in nil },
            createFile: { path, data in recorder.recordCreatedFile(path: path, data: data) },
            removeItem: { _ in XCTFail("Resume data should not be removed on failure") },
            shouldRetry: { _ in false }
        )

        do {
            _ = try await service.downloadWithURLSession(
                url: try XCTUnwrap(URL(string: "https://example.com/Xcode.xip")),
                destination: try XCTUnwrap(Path("/tmp/Xcode-15.xip")),
                resumeDataPath: resumeDataPath,
                progressChanged: { _ in }
            )
            XCTFail("Expected URLSession failure")
        } catch {
            XCTAssertEqual(error as NSError, expectedError)
            XCTAssertEqual(recorder.createdFiles.map(\.path), [resumeDataPath.string])
            XCTAssertEqual(recorder.createdFiles.map(\.data), [failedResumeData])
        }
    }

    func testArchiveDownloadServiceAria2YieldsProgressAndReturnsDestination() async throws {
        let recorder = DownloadRecorder()
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 42
        let destination = try XCTUnwrap(Path("/tmp/Xcode-15.xip"))
        let service = ArchiveDownloadService(
            aria2Download: { _, _, _, _ in
                let (stream, continuation) = AsyncThrowingStream.makeStream(of: Progress.self, throwing: Error.self)
                continuation.yield(progress)
                continuation.finish()
                return stream
            },
            urlSessionDownload: { _, _, _ in
                XCTFail("URLSession should not be used")
                return (Progress(), Task { throw URLError(.unknown) })
            },
            contentsAtPath: { _ in nil },
            createFile: { _, _ in XCTFail("Resume data should not be persisted") },
            removeItem: { _ in XCTFail("Resume data should not be removed") }
        )

        let url = try await service.downloadWithAria2(
            aria2Path: try XCTUnwrap(Path("/usr/bin/aria2c")),
            url: try XCTUnwrap(URL(string: "https://example.com/Xcode.xip")),
            destination: destination,
            cookies: [],
            progressChanged: { recorder.recordProgress($0) }
        )

        XCTAssertEqual(url, destination.url)
        XCTAssertEqual(recorder.progressCount, 1)
    }

    func testArchiveDownloadServiceValidatesDeveloperUnauthorizedRedirect() throws {
        enum UnauthorizedTestError: Error, Equatable {
            case notAuthorized
        }

        let response = try XCTUnwrap(URLResponse(
            url: try XCTUnwrap(URL(string: "https://developer.apple.com/unauthorized/")),
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        ))

        do {
            try ArchiveDownloadService.validateDeveloperDownloadResponse(
                response,
                unauthorizedError: { UnauthorizedTestError.notAuthorized }
            )
            XCTFail("Expected unauthorized redirect to throw")
        } catch let error as UnauthorizedTestError {
            XCTAssertEqual(error, .notAuthorized)
        }
    }

    func testArchiveDownloadServiceAcceptsDeveloperDownloadResponse() throws {
        let response = try XCTUnwrap(URLResponse(
            url: try XCTUnwrap(URL(string: "https://download.developer.apple.com/Developer_Tools/Xcode_15/Xcode_15.xip")),
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        ))

        try ArchiveDownloadService.validateDeveloperDownloadResponse(response)
    }

    func testAvailableXcodeReleaseExposesDownloadPath() throws {
        let release = AvailableXcodeRelease(
            version: try XCTUnwrap(Version("15.0.0")),
            url: try XCTUnwrap(URL(string: "https://example.com/Developer_Tools/Xcode_15/Xcode_15.xip")),
            filename: "Xcode_15.xip",
            releaseDate: nil
        )

        XCTAssertEqual(release.downloadPath, "/Developer_Tools/Xcode_15/Xcode_15.xip")
    }

    func testXcodeListServiceFiltersPrereleasesWithDuplicateBuildMetadata() throws {
        let release = AvailableXcode(
            version: try XCTUnwrap(Version("12.4.0+12D4e")),
            url: try XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
            filename: "mock.xip",
            releaseDate: nil
        )
        let prerelease = AvailableXcode(
            version: try XCTUnwrap(Version("12.4.0-RC+12D4e")),
            url: try XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
            filename: "mock.xip",
            releaseDate: nil
        )

        let filtered = XcodeListService.filteringPrereleasesWithDuplicateBuildMetadata([release, prerelease])

        XCTAssertEqual(filtered.map(\.version), [release.version])
        XCTAssertEqual(XcodeListService.identicalBuildIDs(for: release, in: [release, prerelease]), [
            release.xcodeID,
            prerelease.xcodeID
        ])
    }

    func testXcodeListServiceKeepsArchitectureSpecificPrereleaseWithDuplicateBuildMetadata() throws {
        let release = AvailableXcode(
            version: try XCTUnwrap(Version("16.0.0+16A1")),
            url: try XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
            filename: "mock.xip",
            releaseDate: nil
        )
        let architectureSpecificPrerelease = AvailableXcode(
            version: try XCTUnwrap(Version("16.0.0-RC+16A1")),
            url: try XCTUnwrap(URL(string: "https://apple.com/xcode-arm64.xip")),
            filename: "mock-arm64.xip",
            releaseDate: nil,
            architectures: [.arm64]
        )

        let filtered = XcodeListService.filteringPrereleasesWithDuplicateBuildMetadata([
            release,
            architectureSpecificPrerelease
        ])

        XCTAssertEqual(filtered.map(\.xcodeID), [
            release.xcodeID,
            architectureSpecificPrerelease.xcodeID
        ])
    }

    func testXcodeListServiceValidatesDeveloperDownloads() async throws {
        let downloads = Downloads(
            resultCode: 0,
            resultsString: nil,
            downloads: [
                Download(
                    name: "Xcode 15",
                    files: [Download.File(remotePath: "Developer_Tools/Xcode_15/Xcode_15.xip")],
                    dateModified: Date()
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
        let data = try encoder.encode(downloads)
        let service = XcodeListService { request in
            XCTAssertEqual(request.url, URLRequest.developerDownloads.url)
            return (
                data,
                try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            )
        }

        try await service.validateDeveloperDownloads()
    }

    func testXcodeListServiceMapsDeveloperDownloadsErrorResult() async throws {
        let downloads = Downloads(resultCode: 1, resultsString: "Access denied", downloads: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
        let data = try encoder.encode(downloads)
        let service = XcodeListService { request in
            (
                data,
                try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            )
        }

        do {
            try await service.validateDeveloperDownloads()
            XCTFail("Expected developer downloads validation to throw")
        } catch {
            XCTAssertEqual(error as? XcodeListService.Error, .invalidResult("Access denied"))
        }
    }

    func testXcodeListComposerPreservesInstallingState() throws {
        let version = try XCTUnwrap(Version("15.0.0"))
        let composer = XcodeListComposer()

        let items = composer.compose(
            availableXcodes: [
                AvailableXcode(
                    version: version,
                    url: try XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
                    filename: "mock.xip",
                    releaseDate: nil
                )
            ],
            installedXcodes: [],
            selectedXcodePath: nil,
            existingXcodes: [
                XcodeListItem(
                    version: version,
                    installState: .installing(.unarchiving),
                    selected: false
                )
            ],
            dataSource: .xcodeReleases
        )

        XCTAssertEqual(items.map(\.installState), [.installing(.unarchiving)])
    }

    func testXcodeListComposerAdjustsAppleBuildMetadataUsingInstalledXcodes() throws {
        let composer = XcodeListComposer()
        let installedPath = try XCTUnwrap(Path("/Applications/Xcode.app"))

        let items = composer.compose(
            availableXcodes: [
                AvailableXcode(
                    version: try XCTUnwrap(Version("15.0.0-GM+15A1")),
                    url: try XCTUnwrap(URL(string: "https://apple.com/xcode.xip")),
                    filename: "mock.xip",
                    releaseDate: nil
                )
            ],
            installedXcodes: [
                InstalledXcode(
                    path: installedPath,
                    version: try XCTUnwrap(Version("15.0.0+15A1"))
                )
            ],
            selectedXcodePath: "\(installedPath.string)/Contents/Developer",
            existingXcodes: [],
            dataSource: .apple
        )

        XCTAssertEqual(items.map(\.version), [try XCTUnwrap(Version("15.0.0+15A1"))])
        XCTAssertEqual(items.first?.installState, .installed(installedPath))
        XCTAssertEqual(items.first?.selected, true)
    }

    func testXcodeListPresentationServiceBuildsAvailableRows() throws {
        let selectedPath = try XCTUnwrap(Path("/Applications/Xcode-15.0.app"))
        let installedPath = try XCTUnwrap(Path("/Applications/Xcode-14.0.app"))
        let service = XcodeListPresentationService()
        let newerXcode = AvailableXcode(
            version: try XCTUnwrap(Version("15.0.0")),
            url: try XCTUnwrap(URL(string: "https://apple.com/xcode-15.xip")),
            filename: "xcode-15.xip",
            releaseDate: nil
        )
        let olderXcode = AvailableXcode(
            version: try XCTUnwrap(Version("14.0.0")),
            url: try XCTUnwrap(URL(string: "https://apple.com/xcode-14.xip")),
            filename: "xcode-14.xip",
            releaseDate: nil
        )

        let rows = service.availableRows(
            availableXcodes: [newerXcode, olderXcode],
            installedXcodes: [
                InstalledXcode(path: selectedPath, version: try XCTUnwrap(Version("15.0.0"))),
                InstalledXcode(path: installedPath, version: try XCTUnwrap(Version("14.0.0")))
            ],
            selectedXcodePath: "\(selectedPath.string)/Contents/Developer",
            dataSource: .xcodeReleases
        )

        XCTAssertEqual(rows.map(\.version), [olderXcode.version, newerXcode.version])
        XCTAssertEqual(rows.map(\.isInstalled), [true, true])
        XCTAssertEqual(rows.map(\.isSelected), [false, true])
    }

    func testXcodeListPresentationServiceFormatsInstalledRows() throws {
        let selectedPath = try XCTUnwrap(Path("/Applications/Xcode-15.0.app"))
        let service = XcodeListPresentationService()
        let rows = service.installedRows(
            installedXcodes: [
                InstalledXcode(path: selectedPath, version: try XCTUnwrap(Version("15.0.0"))),
                InstalledXcode(
                    path: try XCTUnwrap(Path("/Applications/Xcode-14.0.app")),
                    version: try XCTUnwrap(Version("14.0.0"))
                )
            ],
            selectedXcodePath: "\(selectedPath.string)/Contents/Developer"
        )

        XCTAssertEqual(rows.map(\.version), [
            try XCTUnwrap(Version("14.0.0")),
            try XCTUnwrap(Version("15.0.0"))
        ])
        XCTAssertEqual(service.installedLines(rows: rows, interactive: false), [
            "14.0\t/Applications/Xcode-14.0.app",
            "15.0 (Selected)\t/Applications/Xcode-15.0.app"
        ])
        XCTAssertEqual(service.installedLines(rows: rows, interactive: true), [
            "14.0            /Applications/Xcode-14.0.app",
            "15.0 (Selected) /Applications/Xcode-15.0.app"
        ])
    }


    func testXcodeArchiveServiceUsesExistingArchiveWhenPresent() async throws {
        let archive = XcodeArchive(
            version: try XCTUnwrap(Version("15.0.0")),
            downloadURL: try XCTUnwrap(URL(string: "https://apple.com/Xcode.xip")),
            filename: "Xcode.xip"
        )
        let service = XcodeArchiveService(
            applicationSupportPath: try XCTUnwrap(Path("/tmp")),
            fileExists: { $0.string == "/tmp/Xcode-15.0.0.xip" },
            download: { _, _, _, _ in
                XCTFail("Expected existing archive to be reused")
                return URL(fileURLWithPath: "/tmp/downloaded.xip")
            }
        )

        let url = try await service.archiveURL(for: archive, downloader: .urlSession, progressChanged: { _ in })

        XCTAssertEqual(url.path, "/tmp/Xcode-15.0.0.xip")
    }

    func testXcodeArchiveServiceRedownloadsIncompleteAria2Archive() async throws {
        let archive = XcodeArchive(
            version: try XCTUnwrap(Version("15.0.0")),
            downloadURL: try XCTUnwrap(URL(string: "https://apple.com/Xcode.xip")),
            filename: "Xcode.xip"
        )
        let service = XcodeArchiveService(
            applicationSupportPath: try XCTUnwrap(Path("/tmp")),
            fileExists: { path in
                path.string == "/tmp/Xcode-15.0.0.xip" || path.string == "/tmp/Xcode-15.0.0.xip.aria2"
            },
            download: { archive, destination, downloader, _ in
                XCTAssertEqual(archive.version, Version("15.0.0")!)
                XCTAssertEqual(destination.string, "/tmp/Xcode-15.0.0.xip")
                XCTAssertEqual(downloader, .aria2)
                return URL(fileURLWithPath: "/tmp/redownloaded.xip")
            }
        )

        let url = try await service.archiveURL(for: archive, downloader: .aria2, progressChanged: { _ in })

        XCTAssertEqual(url.path, "/tmp/redownloaded.xip")
    }

    func testRuntimeServiceMountDMGParsesMountPoint() async throws {
        let service = RuntimeService(
            loadData: { _ in throw URLError(.badServerResponse) },
            installedRuntimesOutput: { XCTFail("Installed runtime loader should not be called"); return (0, "", "") },
            installRuntimeImageOutput: { _ in XCTFail("Install runtime image should not be called"); return (0, "", "") },
            mountDMGOutput: { url in
                XCTAssertEqual(url.path, "/tmp/runtime.dmg")
                return (0, """
                <dict>
                    <key>system-entities</key>
                    <array>
                        <dict>
                        </dict>
                        <dict>
                            <key>mount-point</key>
                            <string>/Volumes/Runtime</string>
                        </dict>
                    </array>
                </dict>
                """, "")
            },
            unmountDMGOutput: { _ in XCTFail("Unmount should not be called"); return (0, "", "") }
        )

        let mountedURL = try await service.mountDMG(dmgUrl: URL(fileURLWithPath: "/tmp/runtime.dmg"))

        XCTAssertEqual(mountedURL.path, "/Volumes/Runtime")
    }

    func testRuntimeServiceMountDMGThrowsWhenMountPointIsMissing() async throws {
        let service = RuntimeService(
            loadData: { _ in throw URLError(.badServerResponse) },
            installedRuntimesOutput: { XCTFail("Installed runtime loader should not be called"); return (0, "", "") },
            installRuntimeImageOutput: { _ in XCTFail("Install runtime image should not be called"); return (0, "", "") },
            mountDMGOutput: { _ in
                return (0, """
                <dict>
                    <key>system-entities</key>
                    <array>
                        <dict>
                        </dict>
                    </array>
                </dict>
                """, "")
            },
            unmountDMGOutput: { _ in XCTFail("Unmount should not be called"); return (0, "", "") }
        )

        do {
            _ = try await service.mountDMG(dmgUrl: URL(fileURLWithPath: "/tmp/runtime.dmg"))
            XCTFail("Expected missing mount point to throw")
        } catch {
            XCTAssertEqual(error as? RuntimeService.Error, .failedMountingDMG)
        }
    }

    func testRuntimeServiceUsesInjectedPackageOperations() async throws {
        let packagePath = try XCTUnwrap(Path("/tmp/runtime.pkg"))
        let expandedPackagePath = try XCTUnwrap(Path("/tmp/runtime-expanded.pkg"))
        let recorder = PathOperationRecorder()
        let service = RuntimeService(
            loadData: { _ in throw URLError(.badServerResponse) },
            installedRuntimesOutput: { XCTFail("Installed runtime loader should not be called"); return (0, "", "") },
            installRuntimeImageOutput: { _ in XCTFail("Install runtime image should not be called"); return (0, "", "") },
            mountDMGOutput: { _ in XCTFail("Mount should not be called"); return (0, "", "") },
            unmountDMGOutput: { _ in XCTFail("Unmount should not be called"); return (0, "", "") },
            expandPkgOutput: { source, destination in
                XCTAssertEqual(source.path, packagePath.url.path)
                XCTAssertEqual(destination.path, expandedPackagePath.url.path)
                recorder.record("expanded")
                return (0, "", "")
            },
            createPkgOutput: { source, destination in
                XCTAssertEqual(source.path, packagePath.url.path)
                XCTAssertEqual(destination.path, expandedPackagePath.url.path)
                recorder.record("created")
                return (0, "", "")
            },
            installPkgOutput: { packageURL, target in
                XCTAssertEqual(packageURL.path, packagePath.url.path)
                XCTAssertEqual(target, expandedPackagePath.url.absoluteString)
                recorder.record("installed")
                return (0, "", "")
            }
        )

        try await service.expand(pkgPath: packagePath, expandedPkgPath: expandedPackagePath)
        try await service.createPkg(pkgPath: packagePath, expandedPkgPath: expandedPackagePath)
        try await service.installPkg(pkgPath: packagePath, expandedPkgPath: expandedPackagePath)

        XCTAssertEqual(recorder.operations, ["expanded", "created", "installed"])
    }

    func testRuntimeServiceDeleteRuntimeMapsProcessError() async throws {
        let process = Process()
        let service = RuntimeService(
            loadData: { _ in throw URLError(.badServerResponse) },
            installedRuntimesOutput: { XCTFail("Installed runtime loader should not be called"); return (0, "", "") },
            installRuntimeImageOutput: { _ in XCTFail("Install runtime image should not be called"); return (0, "", "") },
            mountDMGOutput: { _ in XCTFail("Mount should not be called"); return (0, "", "") },
            unmountDMGOutput: { _ in XCTFail("Unmount should not be called"); return (0, "", "") },
            deleteRuntimeOutput: { identifier in
                XCTAssertEqual(identifier, "runtime-id")
                throw ProcessExecutionError(
                    process: process,
                    terminationStatus: 1,
                    standardOutput: "",
                    standardError: "runtime delete failed"
                )
            }
        )

        do {
            try await service.deleteRuntime(identifier: "runtime-id")
            XCTFail("Expected delete runtime to throw")
        } catch {
            XCTAssertEqual((error as? XcodesKitError)?.message, "runtime delete failed")
        }
    }

    func testRuntimePackageInstallServiceRewritesPackageInstallLocation() async throws {
        let runtime = downloadableRuntime(
            source: nil,
            simulatorVersion: .init(buildUpdate: "19F70", version: "15.5"),
            name: "iOS 15.5"
        )
        let diskImageURL = URL(fileURLWithPath: "/tmp/iOS_15_5.dmg")
        let mountedURL = URL(fileURLWithPath: "/Volumes/iOS 15.5")
        let mountedPackagePath = Path("/Volumes/iOS 15.5/Runtime.pkg")!
        let cachesDirectory = Path("/tmp/xcodes-cache")!
        let expandedPackagePath = cachesDirectory/runtime.identifier
        let repackagedPath = cachesDirectory/(runtime.identifier + ".pkg")
        let packageInfo = """
        <pkg-info postinstall-action="none" auth="root">
        </pkg-info>
        """
        let recorder = RuntimePackageInstallRecorder()

        let service = RuntimePackageInstallService(
            mountDMG: { url in
                XCTAssertEqual(url, diskImageURL)
                recorder.append("mount")
                return mountedURL
            },
            unmountDMG: { url in
                XCTAssertEqual(url, mountedURL)
                recorder.append("unmount")
            },
            packagePath: { url in
                XCTAssertEqual(url, mountedURL)
                return mountedPackagePath
            },
            prepareDirectory: { path in
                XCTAssertEqual(path, cachesDirectory)
                recorder.append("prepare")
            },
            expandPkg: { packageURL, expandedURL in
                XCTAssertEqual(packageURL, mountedPackagePath.url)
                XCTAssertEqual(expandedURL, expandedPackagePath.url)
                recorder.append("expand")
                return (0, "", "")
            },
            createPkg: { expandedURL, packageURL in
                XCTAssertEqual(expandedURL, expandedPackagePath.url)
                XCTAssertEqual(packageURL, repackagedPath.url)
                recorder.append("create")
                return (0, "", "")
            },
            installPkg: { packageURL, target in
                XCTAssertEqual(packageURL, repackagedPath.url)
                XCTAssertEqual(target, "/")
                recorder.append("install")
                return (0, "", "")
            },
            contentsAtPath: { path in
                XCTAssertEqual(path, (expandedPackagePath/"PackageInfo").string)
                recorder.append("read")
                return Data(packageInfo.utf8)
            },
            writeData: { data, url in
                XCTAssertEqual(url, (expandedPackagePath/"PackageInfo").url)
                recorder.append("write")
                recorder.rewrittenPackageInfo = String(data: data, encoding: .utf8)
            },
            removeItem: { _ in }
        )

        try await service.installPackageRuntime(
            from: diskImageURL,
            runtime: runtime,
            cachesDirectory: cachesDirectory
        )

        XCTAssertEqual(recorder.steps, ["mount", "prepare", "expand", "unmount", "read", "write", "create", "install"])
        XCTAssertTrue(recorder.rewrittenPackageInfo?.contains(#"install-location="/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 15.5.simruntime""#) == true)
    }

    func testRuntimePackageInstallServiceUnmountsWhenExpandFails() async throws {
        let runtime = downloadableRuntime(
            source: nil,
            simulatorVersion: .init(buildUpdate: "19F70", version: "15.5"),
            name: "iOS 15.5"
        )
        let diskImageURL = URL(fileURLWithPath: "/tmp/iOS_15_5.dmg")
        let mountedURL = URL(fileURLWithPath: "/Volumes/iOS 15.5")
        let mountedPackagePath = Path("/Volumes/iOS 15.5/Runtime.pkg")!
        let cachesDirectory = Path("/tmp/xcodes-cache")!
        let recorder = RuntimePackageInstallRecorder()

        let service = RuntimePackageInstallService(
            mountDMG: { url in
                XCTAssertEqual(url, diskImageURL)
                recorder.append("mount")
                return mountedURL
            },
            unmountDMG: { url in
                XCTAssertEqual(url, mountedURL)
                recorder.append("unmount")
            },
            packagePath: { url in
                XCTAssertEqual(url, mountedURL)
                return mountedPackagePath
            },
            prepareDirectory: { path in
                XCTAssertEqual(path, cachesDirectory)
                recorder.append("prepare")
            },
            expandPkg: { _, _ in
                recorder.append("expand")
                throw XcodesKitError("expand failed")
            },
            createPkg: { _, _ in
                XCTFail("Create should not be called")
                return (0, "", "")
            },
            installPkg: { _, _ in
                XCTFail("Install should not be called")
                return (0, "", "")
            },
            contentsAtPath: { _ in
                XCTFail("PackageInfo should not be read")
                return nil
            },
            writeData: { _, _ in
                XCTFail("PackageInfo should not be written")
            },
            removeItem: { _ in }
        )

        do {
            try await service.installPackageRuntime(
                from: diskImageURL,
                runtime: runtime,
                cachesDirectory: cachesDirectory
            )
            XCTFail("Expected package install to fail")
        } catch let error as XcodesKitError {
            XCTAssertEqual(error.message, "expand failed")
        }

        XCTAssertEqual(recorder.steps, ["mount", "prepare", "expand", "unmount"])
    }

    func testRuntimeArchiveInstallServiceInstallsDiskImageAndDeletesArchive() async throws {
        let recorder = PathOperationRecorder()
        let archiveURL = URL(fileURLWithPath: "/tmp/iOS_16_Runtime.dmg")
        let service = RuntimeArchiveInstallService(
            installDiskImage: { url in
                recorder.record("install:\(url.path)")
            },
            removeArchive: { url in
                recorder.record("remove:\(url.path)")
            }
        )

        try await service.install(
            runtime: downloadableRuntime(source: "https://example.com/iOS_16_Runtime.dmg"),
            archiveURL: archiveURL,
            stepChanged: { step in
                recorder.record("step:\(step)")
            }
        )

        XCTAssertEqual(recorder.operations, [
            "step:(2/3) Installing",
            "install:/tmp/iOS_16_Runtime.dmg",
            "step:(3/3) TrashingArchive",
            "remove:/tmp/iOS_16_Runtime.dmg"
        ])
    }

    func testRuntimeArchiveInstallServiceCanKeepArchive() async throws {
        let recorder = PathOperationRecorder()
        let archiveURL = URL(fileURLWithPath: "/tmp/iOS_16_Runtime.dmg")
        let service = RuntimeArchiveInstallService(
            installDiskImage: { _ in
                recorder.record("install")
            },
            removeArchive: { _ in
                recorder.record("remove")
            }
        )

        try await service.install(
            runtime: downloadableRuntime(source: "https://example.com/iOS_16_Runtime.dmg"),
            archiveURL: archiveURL,
            deleteArchive: false
        )

        XCTAssertEqual(recorder.operations, ["install"])
    }

    func testRuntimeArchiveInstallServiceRejectsUnsupportedArchiveTypes() async throws {
        let archiveURL = URL(fileURLWithPath: "/tmp/iOS_15_Runtime.dmg")
        let service = RuntimeArchiveInstallService(
            installDiskImage: { _ in
                XCTFail("Expected unsupported archive to skip disk image install")
            },
            removeArchive: { _ in
                XCTFail("Expected unsupported archive to skip cleanup")
            }
        )

        do {
            try await service.install(
                runtime: downloadableRuntime(
                    source: "https://example.com/iOS_15_Runtime.dmg",
                    contentType: .package
                ),
                archiveURL: archiveURL
            )
            XCTFail("Expected unsupported content type error")
        } catch let error as RuntimeArchiveInstallError {
            XCTAssertEqual(error, .unsupportedContentType(.package, archiveURL: archiveURL))
        }
    }

    func testDownloadableRuntimeCacheLoadsAndSavesRuntimes() throws {
        let runtime = downloadableRuntime(source: "https://example.com/iOS.dmg")
        let cacheFile = try XCTUnwrap(Path("/tmp/downloadable-runtimes.json"))
        let recorder = RuntimeCacheFileRecorder()
        let cache = DownloadableRuntimeCache(
            cacheFile: cacheFile,
            contentsAtPath: { _ in recorder.storedData },
            writeData: { data, url in
                recorder.recordWrite(data: data, url: url)
            },
            createDirectory: { url, _, _ in
                recorder.recordCreatedDirectory(url)
            }
        )

        XCTAssertNil(try cache.load())

        try cache.save([runtime])

        let loadedRuntimes = try XCTUnwrap(try cache.load())
        XCTAssertEqual(loadedRuntimes, [runtime])
        XCTAssertEqual(recorder.createdDirectory?.path, "/tmp")
        XCTAssertEqual(recorder.writtenURL?.path, cacheFile.url.path)
    }

    func testDownloadableRuntimesResponseAddsSDKBuildUpdates() {
        let response = DownloadableRuntimesResponse(
            sdkToSimulatorMappings: [
                SDKToSimulatorMapping(
                    sdkBuildUpdate: "22A3362",
                    simulatorBuildUpdate: "20A360",
                    sdkIdentifier: "iphonesimulator",
                    downloadableIdentifiers: nil
                )
            ],
            sdkToSeedMappings: [],
            refreshInterval: 3600,
            downloadables: [downloadableRuntime(source: "https://example.com/iOS_16_Runtime.dmg")],
            version: "2"
        )

        XCTAssertEqual(response.downloadablesWithSDKBuildUpdates().first?.sdkBuildUpdate, ["22A3362"])
    }

    func testRuntimeListPresentationServiceBuildsInstalledRows() {
        let response = DownloadableRuntimesResponse(
            sdkToSimulatorMappings: [],
            sdkToSeedMappings: [],
            refreshInterval: 3600,
            downloadables: [downloadableRuntime(source: "https://example.com/iOS_16_Runtime.dmg")],
            version: "2"
        )
        let service = RuntimeListPresentationService()

        let rows = service.rows(
            downloadableRuntimes: response,
            installedRuntimes: [
                installedRuntime(build: "20A360", kind: .diskImage)
            ],
            includeBetas: false
        )

        XCTAssertEqual(rows.map(\.platform.shortName), ["iOS"])
        XCTAssertEqual(rows.first?.runtimes.map { service.line(for: $0) }, [
            "iOS 16.0 (Installed)"
        ])
    }

    func testRuntimeListPresentationServiceHidesUnavailableBetas() {
        let response = DownloadableRuntimesResponse(
            sdkToSimulatorMappings: [],
            sdkToSeedMappings: [],
            refreshInterval: 3600,
            downloadables: [
                downloadableRuntime(
                    source: "https://example.com/iOS_17_Runtime.dmg",
                    simulatorVersion: .init(buildUpdate: "21A1", version: "17.0"),
                    identifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0-b1",
                    name: "iOS 17.0 beta"
                )
            ],
            version: "2"
        )

        let rows = RuntimeListPresentationService().rows(
            downloadableRuntimes: response,
            installedRuntimes: [],
            includeBetas: false
        )

        XCTAssertEqual(rows.first?.runtimes.map(\.visibleIdentifier), [])
    }

    func testRuntimeInstallPolicyUsesArchiveForLegacyRuntime() throws {
        let method = try RuntimeInstallPolicy().installMethod(
            for: downloadableRuntime(source: "https://example.com/iOS_16_Runtime.dmg"),
            selectedXcodeVersion: nil
        )

        XCTAssertEqual(method, .archive)
    }

    func testRuntimeInstallPolicyRequiresSelectedXcodeForCryptexRuntime() {
        let runtime = downloadableRuntime(
            source: nil,
            contentType: .cryptexDiskImage
        )

        XCTAssertThrowsError(try RuntimeInstallPolicy().installMethod(for: runtime, selectedXcodeVersion: nil)) { error in
            XCTAssertEqual(error as? RuntimeInstallPolicyError, .noSelectedXcode)
        }
    }

    func testRuntimeInstallPolicyRequiresXcode26ForAppleSiliconCryptexRuntime() {
        let runtime = downloadableRuntime(
            source: nil,
            architectures: [.arm64],
            contentType: .cryptexDiskImage
        )

        XCTAssertThrowsError(try RuntimeInstallPolicy().installMethod(for: runtime, selectedXcodeVersion: Version("16.4.0")!)) { error in
            XCTAssertEqual(error as? RuntimeInstallPolicyError, .xcode26OrGreaterRequired(Version("16.4.0")!))
        }
    }

    func testRuntimeInstallPolicyUsesXcodebuildForSupportedCryptexRuntime() throws {
        let runtime = downloadableRuntime(
            source: nil,
            architectures: [.arm64],
            contentType: .cryptexDiskImage
        )

        let method = try RuntimeInstallPolicy().installMethod(
            for: runtime,
            selectedXcodeVersion: Version("26.0.0")!
        )

        XCTAssertEqual(method, .xcodebuild(architecture: "arm64"))
    }

    func testRuntimeInstallPolicyParsesXcodebuildVersionOutput() {
        let version = RuntimeInstallPolicy().selectedXcodeVersion(
            fromXcodebuildVersionOutput: """
            Xcode 16.4
            Build version 16F6
            """
        )

        XCTAssertEqual(version, Version("16.4.0")!)
    }

    func testRuntimeXcodebuildInstallServiceDownloadsRuntimeAndYieldsProgress() async throws {
        let recorder = PathOperationRecorder()
        let service = RuntimeXcodebuildInstallService { platform, buildVersion, architecture in
            recorder.record("download:\(platform):\(buildVersion):\(architecture ?? "nil")")
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: Progress.self, throwing: Error.self)
            let firstProgress = Progress(totalUnitCount: 100)
            firstProgress.completedUnitCount = 25
            let secondProgress = Progress(totalUnitCount: 100)
            secondProgress.completedUnitCount = 100

            continuation.yield(firstProgress)
            continuation.yield(secondProgress)
            continuation.finish()

            return stream
        }

        try await service.downloadAndInstall(
            runtime: downloadableRuntime(source: "https://example.com/runtime.dmg"),
            architecture: "arm64"
        ) { progress in
            recorder.record("progress:\(progress.completedUnitCount)")
        }

        XCTAssertEqual(recorder.operations, [
            "download:iOS:20A360:arm64",
            "progress:25",
            "progress:100"
        ])
    }

    func testRuntimeXcodebuildInstallServiceStopsProgressWhenCancelled() async throws {
        let recorder = PathOperationRecorder()
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Progress.self, throwing: Error.self)
        let service = RuntimeXcodebuildInstallService { platform, buildVersion, architecture in
            recorder.record("download:\(platform):\(buildVersion):\(architecture ?? "nil")")
            return stream
        }
        let runtime = downloadableRuntime(source: "https://example.com/runtime.dmg")

        let task = Task {
            try await service.downloadAndInstall(
                runtime: runtime,
                architecture: "arm64"
            ) { progress in
                recorder.record("progress:\(progress.completedUnitCount)")
            }
        }

        while recorder.operations.isEmpty {
            await Task.yield()
        }

        task.cancel()
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 25
        continuation.yield(progress)
        continuation.finish()

        do {
            try await task.value
            XCTFail("Expected cancellation to be thrown")
        } catch is CancellationError {
        }

        XCTAssertEqual(recorder.operations, [
            "download:iOS:20A360:arm64"
        ])
    }

    func testRuntimeArchiveServiceUsesExistingArchiveWhenPresent() async throws {
        let runtime = downloadableRuntime(source: "https://example.com/iOS_16_Runtime.dmg")
        let service = RuntimeArchiveService(
            fileExists: { $0.string == "/tmp/iOS_16_Runtime.dmg" },
            download: { _, _, _, _, _ in
                XCTFail("Expected existing runtime archive to be reused")
                return URL(fileURLWithPath: "/tmp/downloaded.dmg")
            }
        )

        let url = try await service.archiveURL(
            for: runtime,
            destinationDirectory: try XCTUnwrap(Path("/tmp")),
            downloader: .aria2,
            progressChanged: { _ in }
        )

        XCTAssertEqual(url.path, "/tmp/iOS_16_Runtime.dmg")
    }

    func testRuntimeArchiveServiceRedownloadsIncompleteAria2Archive() async throws {
        let runtime = downloadableRuntime(source: "https://example.com/iOS_16_Runtime.dmg")
        let service = RuntimeArchiveService(
            fileExists: { path in
                path.string == "/tmp/iOS_16_Runtime.dmg" || path.string == "/tmp/iOS_16_Runtime.dmg.aria2"
            },
            download: { runtime, url, destination, downloader, _ in
                XCTAssertEqual(runtime.visibleIdentifier, "iOS 16.0")
                XCTAssertEqual(url.absoluteString, "https://example.com/iOS_16_Runtime.dmg")
                XCTAssertEqual(destination.string, "/tmp/iOS_16_Runtime.dmg")
                XCTAssertEqual(downloader, .aria2)
                return URL(fileURLWithPath: "/tmp/redownloaded.dmg")
            }
        )

        let url = try await service.archiveURL(
            for: runtime,
            destinationDirectory: try XCTUnwrap(Path("/tmp")),
            downloader: .aria2,
            progressChanged: { _ in }
        )

        XCTAssertEqual(url.path, "/tmp/redownloaded.dmg")
    }

    func testRuntimeInstallationLookupServiceFindsInstalledRuntimeByBuild() {
        let runtime = downloadableRuntime(source: "https://example.com/iOS_16_Runtime.dmg")
        let installedRuntime = coreSimulatorImage(
            build: runtime.simulatorVersion.buildUpdate,
            path: "file:///Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 16.simruntime"
        )

        let service = RuntimeInstallationLookupService()

        XCTAssertEqual(
            service.coreSimulatorImage(for: runtime, in: [installedRuntime])?.uuid,
            installedRuntime.uuid
        )
        XCTAssertEqual(
            service.installPath(for: runtime, in: [installedRuntime])?.string,
            "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 16.simruntime"
        )
    }

    func testRuntimeInstallationLookupServiceMatchesArchitecturesWhenRuntimeRequiresThem() {
        let runtime = downloadableRuntime(
            source: "https://example.com/iOS_16_Runtime.dmg",
            architectures: [.arm64]
        )
        let x86Runtime = coreSimulatorImage(
            build: runtime.simulatorVersion.buildUpdate,
            supportedArchitectures: [.x86_64]
        )
        let armRuntime = coreSimulatorImage(
            build: runtime.simulatorVersion.buildUpdate,
            supportedArchitectures: [.arm64]
        )

        let image = RuntimeInstallationLookupService().coreSimulatorImage(
            for: runtime,
            in: [x86Runtime, armRuntime]
        )

        XCTAssertEqual(image?.uuid, armRuntime.uuid)
    }

    func testProcessProgressStreamRunnerYieldsOutputProgress() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf 'Downloading iOS Simulator: 42.0%% (1.2 GB of 2.8 GB)'"]
        let collector = ProcessOutputCollector()
        let progress = Progress()

        let stream = ProcessProgressStreamRunner(
            process: process,
            progress: progress,
            outputHandler: { string, progress in
                collector.append(string)
                progress.updateFromXcodebuild(text: string)
            },
            failureHandler: { process in
                ProcessExecutionError(process: process, standardOutput: "", standardError: "")
            }
        ).stream()

        var emittedProgress: [Progress] = []
        for try await progress in stream {
            emittedProgress.append(progress)
        }

        XCTAssertEqual(collector.output, "Downloading iOS Simulator: 42.0% (1.2 GB of 2.8 GB)")
        XCTAssertFalse(emittedProgress.isEmpty)
        XCTAssertEqual(progress.fractionCompleted, 0.42, accuracy: 0.001)
    }

    func testProcessProgressStreamRunnerDrainsLargeOutputWhileProcessIsRunning() async throws {
        let line = String(repeating: "0123456789abcdef", count: 16)
        let lineCount = 20_000

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "yes '\(line)' | head -n \(lineCount)"
        ]

        let collector = ProcessOutputCollector()
        let stream = ProcessProgressStreamRunner(
            process: process,
            progress: Progress(),
            outputHandler: { string, _ in
                collector.append(string)
            },
            failureHandler: { process in
                ProcessExecutionError(process: process, standardOutput: "", standardError: "")
            }
        ).stream()

        for try await _ in stream {}

        let expectedOutput = String(repeating: "\(line)\n", count: lineCount)
        XCTAssertEqual(collector.output, expectedOutput)
    }

    func testProcessProgressStreamRunnerThrowsFailureHandlerError() async {
        enum TestError: Error, Equatable {
            case failed(Int32)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exit 12"]

        let stream = ProcessProgressStreamRunner(
            process: process,
            progress: Progress(),
            outputHandler: { _, _ in },
            failureHandler: { process in
                TestError.failed(process.terminationStatus)
            }
        ).stream()

        do {
            for try await _ in stream {}
            XCTFail("Expected process failure to throw")
        } catch {
            XCTAssertEqual(error as? TestError, .failed(12))
        }
    }

    func testAsyncProcessRunnerDrainsLargeOutputWhileProcessIsRunning() async throws {
        let line = String(repeating: "0123456789abcdef", count: 16)
        let lineCount = 20_000

        let output = try await XcodesProcess.run(
            URL(fileURLWithPath: "/bin/sh"),
            [
                "-c",
                "yes '\(line)' | head -n \(lineCount)"
            ]
        )

        XCTAssertEqual(output.status, 0)
        XCTAssertTrue(output.err.isEmpty)
        XCTAssertEqual(output.out.split(separator: "\n").count, lineCount)
    }

    private func downloadableRuntime(
        source: String?,
        architectures: [Architecture]? = nil,
        contentType: DownloadableRuntime.ContentType = .diskImage,
        simulatorVersion: DownloadableRuntime.SimulatorVersion = .init(buildUpdate: "20A360", version: "16.0"),
        identifier: String = "com.apple.CoreSimulator.SimRuntime.iOS-16-0",
        name: String = "iOS 16.0"
    ) -> DownloadableRuntime {
        DownloadableRuntime(
            category: .simulator,
            simulatorVersion: simulatorVersion,
            source: source,
            architectures: architectures,
            dictionaryVersion: 1,
            contentType: contentType,
            platform: .iOS,
            identifier: identifier,
            version: simulatorVersion.version,
            fileSize: 42,
            hostRequirements: nil,
            name: name,
            authentication: nil
        )
    }

    private func installedRuntime(build: String, kind: InstalledRuntime.Kind) -> InstalledRuntime {
        InstalledRuntime(
            build: build,
            deletable: true,
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            kind: kind,
            lastUsedAt: nil,
            path: "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 16.simruntime",
            platformIdentifier: .iOS,
            runtimeBundlePath: "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 16.simruntime",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-16-0",
            signatureState: "Verified",
            state: "Ready",
            version: "16.0",
            sizeBytes: 42,
            supportedArchitectures: nil
        )
    }

    private func coreSimulatorImage(
        build: String,
        path: String = "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 16.simruntime",
        supportedArchitectures: [Architecture]? = nil
    ) -> CoreSimulatorImage {
        CoreSimulatorImage(
            uuid: UUID().uuidString,
            path: ["relative": path],
            runtimeInfo: CoreSimulatorRuntimeInfo(
                build: build,
                supportedArchitectures: supportedArchitectures
            )
        )
    }
}

private actor XcodePostInstallRecorder {
    private(set) var didRunFirstLaunch = false
    private(set) var touchedInstallCheck: (cacheDirectory: String, macOSBuildVersion: String, toolsVersion: String)?

    func recordFirstLaunch() {
        didRunFirstLaunch = true
    }

    func recordInstallCheck(cacheDirectory: String, macOSBuildVersion: String, toolsVersion: String) {
        touchedInstallCheck = (cacheDirectory, macOSBuildVersion, toolsVersion)
    }
}

private enum XcodeInstallRetryTestError: Error, Equatable {
    case damagedArchive(URL)
}

private actor XcodeArchiveInstallStepRecorder {
    private var steps: [XcodeArchiveInstallStep] = []

    func record(_ step: XcodeArchiveInstallStep) {
        steps.append(step)
    }

    func recordedSteps() -> [XcodeArchiveInstallStep] {
        steps
    }
}

private enum XcodePostInstallPreparationEvent: Equatable {
    case enableDeveloperTools
    case addStaffToDevelopersGroup
    case acceptLicense
}

private actor XcodePostInstallPreparationRecorder {
    private(set) var events: [XcodePostInstallPreparationEvent] = []

    func record(_ event: XcodePostInstallPreparationEvent) {
        events.append(event)
    }
}

private actor RetryRecorder<Value> {
    private(set) var values: [Value] = []

    var count: Int {
        values.count
    }

    @discardableResult
    func record(_ value: Value) -> Int {
        values.append(value)
        return values.count
    }
}

private final class DownloadRecorder: Sendable {
    private struct State: Sendable {
        var urlSessionResumeData: Data?
        var removedURLs: [URL] = []
        var createdFiles: [(path: String, data: Data)] = []
        var progressCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var urlSessionResumeData: Data? {
        state.withLock { $0.urlSessionResumeData }
    }

    var removedURLs: [URL] {
        state.withLock { $0.removedURLs }
    }

    var createdFiles: [(path: String, data: Data)] {
        state.withLock { $0.createdFiles }
    }

    var progressCount: Int {
        state.withLock { $0.progressCount }
    }

    func recordURLSession(url: URL, destination: URL, resumeData: Data?) {
        state.withLock { $0.urlSessionResumeData = resumeData }
    }

    func recordRemovedURL(_ url: URL) {
        state.withLock { $0.removedURLs.append(url) }
    }

    func recordCreatedFile(path: String, data: Data) {
        state.withLock { $0.createdFiles.append((path, data)) }
    }

    func recordProgress(_ progress: Progress) {
        state.withLock { $0.progressCount += 1 }
    }
}

private final class ProcessOutputCollector: Sendable {
    private let chunks = OSAllocatedUnfairLock(initialState: [String]())

    var output: String {
        chunks.withLock { $0.joined() }
    }

    func append(_ chunk: String) {
        chunks.withLock { $0.append(chunk) }
    }
}

private final class URLRecorder: Sendable {
    private let storedURL = OSAllocatedUnfairLock<URL?>(initialState: nil)

    var url: URL? {
        storedURL.withLock { $0 }
    }

    func record(_ url: URL) {
        storedURL.withLock { $0 = url }
    }
}

private final class URLListRecorder: Sendable {
    private let storedURLs = OSAllocatedUnfairLock(initialState: [URL]())

    var paths: [String] {
        storedURLs.withLock { $0.map(\.path) }
    }

    func record(_ url: URL) {
        storedURLs.withLock { $0.append(url) }
    }
}

private final class PathOperationRecorder: Sendable {
    private let storedOperations = OSAllocatedUnfairLock(initialState: [String]())

    var operations: [String] {
        storedOperations.withLock { $0 }
    }

    func record(_ operation: String) {
        storedOperations.withLock { $0.append(operation) }
    }
}

private final class RuntimePackageInstallRecorder: Sendable {
    private struct State: Sendable {
        var steps: [String] = []
        var packageInfo: String?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var steps: [String] {
        state.withLock { $0.steps }
    }

    var rewrittenPackageInfo: String? {
        get {
            state.withLock { $0.packageInfo }
        }
        set {
            state.withLock { $0.packageInfo = newValue }
        }
    }

    func append(_ step: String) {
        state.withLock { $0.steps.append(step) }
    }
}

private final class RuntimeCacheFileRecorder: Sendable {
    private struct State: Sendable {
        var data: Data?
        var directory: URL?
        var url: URL?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var storedData: Data? {
        state.withLock { $0.data }
    }

    var createdDirectory: URL? {
        state.withLock { $0.directory }
    }

    var writtenURL: URL? {
        state.withLock { $0.url }
    }

    func recordWrite(data: Data, url: URL) {
        state.withLock {
            $0.data = data
            $0.url = url
        }
    }

    func recordCreatedDirectory(_ url: URL) {
        state.withLock { $0.directory = url }
    }
}
