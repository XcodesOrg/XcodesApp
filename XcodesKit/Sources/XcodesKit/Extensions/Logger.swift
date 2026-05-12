import Foundation
import os.log

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "eu.mpwg.xcodes"

    static public let appState = Logger(subsystem: subsystem, category: "appState")
    static public let helperClient = Logger(subsystem: subsystem, category: "helperClient")
    static public let subprocess = Logger(subsystem: subsystem, category: "subprocess")
}
