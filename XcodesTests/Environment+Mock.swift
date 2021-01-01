import Combine
import Foundation
@testable import Xcodes

extension Environment {
    static var mock = Environment(
        shell: .mock,
        files: .mock,
        network: .mock,
        logging: .mock,
        keychain: .mock,
        defaults: .mock,
        date: Date.mock,
        helper: .mock
    )
}

extension Shell {
    static var processOutputMock: ProcessOutput = (0, "", "")

    static var mock = Shell(
        unxip: { _ in return Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        spctlAssess: { _ in return Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        codesignVerify: { _ in return Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        buildVersion: { return Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        xcodeBuildVersion: { _ in return Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        getUserCacheDir: { return Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        touchInstallCheck: { _, _, _ in return Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() },
        xcodeSelectPrintPath: { return Just(Shell.processOutputMock).setFailureType(to: Error.self).eraseToAnyPublisher() }
    )
}

extension Files {
    static var mock = Files(
        fileExistsAtPath: { _ in return true },
        moveItem: { _, _ in return },
        contentsAtPath: { path in
            if path.contains("Info.plist") {
                let url = Bundle.xcodesTests.url(forResource: "Stub-0.0.0.Info", withExtension: "plist")!
                return try? Data(contentsOf: url)
            }
            else if path.contains("version.plist") {
                let url = Bundle.xcodesTests.url(forResource: "Stub.version", withExtension: "plist")!
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

extension Network {
    static var mock = Network(
        dataTask: { url in
            Just((data: Data(), response: HTTPURLResponse(url: url.url!, statusCode: 200, httpVersion: nil, headerFields: nil)! as URLResponse))
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        },
        downloadTask: { url, saveLocation, _ in 
            return (
                Progress(),
                Just((saveLocation, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!))
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            ) 
        }
    )
}

extension Logging {
    static var mock = Logging(
        log: { print($0) }
    )
}

extension Keychain {
    static var mock = Keychain(
        getString: { _ in return nil },
        set: { _, _ in },
        remove: { _ in }
    )
}

extension Defaults {
    static var mock = Defaults(
        string: { _ in nil },
        date: { _ in nil },
        setDate: { _, _ in },
        set: { _, _ in },
        removeObject: { _ in }
    )
}

extension Date {
    static var mock = { Date(timeIntervalSince1970: 1609479735) }
}

extension Helper {
    static var mock = Helper(
        install: { },
        checkIfLatestHelperIsInstalled: { Just(false).eraseToAnyPublisher() },
        getVersion: { Just("").setFailureType(to: Error.self).eraseToAnyPublisher() },
        switchXcodePath: { _ in Just(()).setFailureType(to: Error.self).eraseToAnyPublisher() }
    )
}
