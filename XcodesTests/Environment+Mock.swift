import Foundation
import XcodesKit
@testable import Xcodes

func syncXcodesKitMocks() {
    configureXcodesKitFileContents { Xcodes.Current.files.contents(atPath: $0) }
    configureXcodesKitArchs { _ in Shell.processOutputMock }
}

extension Xcodes.Environment {
    static var mock: Xcodes.Environment {
        Xcodes.Environment(
            shell: .mock,
            files: .mock,
            network: .mock,
            keychain: .mock,
            defaults: .mock,
            date: Date.mock,
            helper: .mock
        )
    }
}

extension Shell {
    static let processOutputMock: ProcessOutput = (0, "", "")

    static var mock: Shell {
        Shell(
            unxip: { _ in Shell.processOutputMock },
            spctlAssess: { _ in Shell.processOutputMock },
            codesignVerify: { _ in Shell.processOutputMock },
            buildVersion: { Shell.processOutputMock },
            xcodeBuildVersion: { _ in Shell.processOutputMock },
            archs: { _ in Shell.processOutputMock },
            getUserCacheDir: { Shell.processOutputMock },
            touchInstallCheck: { _, _, _ in Shell.processOutputMock },
            xcodeSelectPrintPath: { Shell.processOutputMock }
        )
    }
}

extension Files {
    static var mock: Files {
        Files(
            fileExistsAtPath: { _ in return true },
            moveItem: { _, _ in return },
            contentsAtPath: { path in
                if path.contains("Info.plist") {
                    let url = Bundle.xcodesTests.url(forResource: "Stub-0.0.0.Info", withExtension: "plist")!
                    return try? Data(contentsOf: url)
                }
                else if path.contains("version.plist") {
                    let url = Bundle.xcodesTests.url(forResource: "Stub-version", withExtension: "plist")!
                    return try? Data(contentsOf: url)
                }
                else {
                    return nil
                }
            },
            removeItem: { _ in },
            trashItem: { _ in return URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash") },
            createFile: { _, _, _ in return true },
            createDirectory: { _, _, _ in },
            installedXcodes: { _ in [] }
        )
    }
}

extension Network {
    static var mock: Network {
        Network(
            session: URLSession.shared,
            loadData: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)! as URLResponse)
            },
            downloadTaskAsync: { url, saveLocation, _ in
                (
                    Progress(),
                    Task {
                        (saveLocation, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                    }
                )
            },
            validateSessionAsync: { },
            signout: { }
        )
    }
}

extension Keychain {
    static var mock: Keychain {
        Keychain(
            getString: { _ in return nil },
            set: { _, _ in },
            remove: { _ in }
        )
    }
}

extension Defaults {
    static var mock: Defaults {
        Defaults(
            string: { _ in nil },
            date: { _ in nil },
            setDate: { _, _ in },
            set: { _, _ in },
            removeObject: { _ in }
        )
    }
}

extension Date {
    static let mock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1609479735) }
}

extension Helper {
    static var mock: Helper {
        Helper(
            install: { },
            checkIfLatestHelperIsInstalledAsync: { false },
            getVersionAsync: { "" },
            switchXcodePathAsync: { _ in },
            devToolsSecurityEnableAsync: { },
            addStaffToDevelopersGroupAsync: { },
            acceptXcodeLicenseAsync: { _ in },
            runFirstLaunchAsync: { _ in }
        )
    }
}
