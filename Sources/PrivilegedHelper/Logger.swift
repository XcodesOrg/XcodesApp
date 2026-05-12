import Foundation
import os.log

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!

    static let connectionVerifier = Logger(subsystem: subsystem, category: "connectionVerifier")
    static let xpcDelegate = Logger(subsystem: subsystem, category: "xpcDelegate")
}
