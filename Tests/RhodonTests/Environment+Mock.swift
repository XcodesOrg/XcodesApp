import Foundation
@testable import Rhodon

extension Rhodon.RhodonEnvironment {
    static let mock = Rhodon.RhodonEnvironment(
        shell: .mock,
        files: .mock,
        network: .mock,
        keychain: .mock,
        defaults: .mock,
        date: Date.mock,
        helper: .mock
    )
}

extension Shell {
    static let processOutputMock = ProcessOutput(status: 0, out: "", err: "")

    static let mock = Shell(
        unxip: { _ in Shell.processOutputMock },
        spctlAssess: { _ in Shell.processOutputMock },
        codesignVerify: { _ in Shell.processOutputMock },
        buildVersion: { Shell.processOutputMock },
        xcodeBuildVersion: { _ in Shell.processOutputMock },
        getUserCacheDir: { Shell.processOutputMock },
        touchInstallCheck: { _, _, _ in
            Shell.processOutputMock
        },
        xcodeSelectPrintPath: { Shell.processOutputMock },
        aria2Path: { nil }
    )
}

extension Files {
    static let mock = Files(
        fileExistsAtPath: { _ in true },
        moveItem: { _, _ in },
        contentsAtPath: { path in
            if path.contains("Info.plist") {
                let url = Bundle.rhodonTests.url(forResource: "Stub-0.0.0.Info", withExtension: "plist")!
                return try? Data(contentsOf: url)
            } else if path.contains("version.plist") {
                let url = Bundle.rhodonTests.url(forResource: "Stub-version", withExtension: "plist")!
                return try? Data(contentsOf: url)
            } else {
                return nil
            }
        },
        removeItem: { _ in },
        trashItem: { _ in URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash") },
        createFile: { _, _, _ in true },
        createDirectory: { _, _, _ in },
        installedRhodon: { _ in [] }
    )
}

extension Network {
    static let mock = Network(
        data: { request in
            (
                Data(),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )! as URLResponse
            )
        },
        downloadTask: { url, saveLocation, _ in
            (
                Progress(),
                Task {
                    (saveLocation, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
            )
        },
        validateSession: {
        }
    )
}

extension Keychain {
    static let mock = Keychain(
        getString: { _ in nil },
        set: { _, _ in },
        remove: { _ in }
    )
}

extension Defaults {
    static let mock = Defaults(
        string: { _ in nil },
        date: { _ in nil },
        setDate: { _, _ in },
        set: { _, _ in },
        removeObject: { _ in }
    )
}

extension Date {
    static let mock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_609_479_735) }
}

extension Helper {
    static let mock = Helper(
        install: {},
        checkIfLatestHelperIsInstalled: { false },
        getVersion: { "" },
        switchXcodePath: { _ in },
        devToolsSecurityEnable: {},
        addStaffToDevelopersGroup: {},
        acceptXcodeLicense: { _ in },
        runFirstLaunch: { _ in }
    )
}
