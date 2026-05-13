import Combine
import Foundation
@testable import Xcodes

extension Xcodes.Environment {
    static let mock = Xcodes.Environment(
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
        unxip: { _ in Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        spctlAssess: { _ in Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        codesignVerify: { _ in Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        buildVersion: { Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        xcodeBuildVersion: { _ in Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        getUserCacheDir: { Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        touchInstallCheck: { _, _, _ in
            Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher()
        },
        xcodeSelectPrintPath: { Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        aria2Path: { nil }
    )
}

extension Files {
    static let mock = Files(
        fileExistsAtPath: { _ in true },
        moveItem: { _, _ in },
        contentsAtPath: { path in
            if path.contains("Info.plist") {
                let url = Bundle.xcodesTests.url(forResource: "Stub-0.0.0.Info", withExtension: "plist")!
                return try? Data(contentsOf: url)
            } else if path.contains("version.plist") {
                let url = Bundle.xcodesTests.url(forResource: "Stub-version", withExtension: "plist")!
                return try? Data(contentsOf: url)
            } else {
                return nil
            }
        },
        removeItem: { _ in },
        trashItem: { _ in URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash") },
        createFile: { _, _, _ in true },
        createDirectory: { _, _, _ in },
        installedXcodes: { _ in [] }
    )
}

extension Network {
    static let mock = Network(
        dataTask: { url in
            Just((
                data: Data(),
                response: HTTPURLResponse(
                    url: url.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )! as URLResponse
            ))
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
        },
        downloadTask: { url, saveLocation, _ in
            (
                Progress(),
                Just((saveLocation, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!))
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            )
        },
        validateSession: {
            Just(())
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        },
        validateSessionAsync: {}
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
        checkIfLatestHelperIsInstalled: { Just(false).eraseToAnyPublisher() },
        getVersion: { Just("").setFailureType(to: Error.self).eraseToAnyPublisher() },
        switchXcodePath: { _ in Just(()).setFailureType(to: Error.self).eraseToAnyPublisher() },
        devToolsSecurityEnable: { Just(()).setFailureType(to: Error.self).eraseToAnyPublisher() },
        addStaffToDevelopersGroup: { Just(()).setFailureType(to: Error.self).eraseToAnyPublisher() },
        acceptXcodeLicense: { _ in Just(()).setFailureType(to: Error.self).eraseToAnyPublisher() },
        runFirstLaunch: { _ in Just(()).setFailureType(to: Error.self).eraseToAnyPublisher() }
    )
}
