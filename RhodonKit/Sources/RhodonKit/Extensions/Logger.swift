import Foundation
import os.log

public extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "eu.mpwg.rhodon"

    static let appState = Logger(subsystem: subsystem, category: "appState")
    static let helperClient = Logger(subsystem: subsystem, category: "helperClient")
    static let subprocess = Logger(subsystem: subsystem, category: "subprocess")
}
