import Foundation
import os.log

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "eu.mpwg.xcodes.Helper"

    static let connectionVerifier = Logger(subsystem: subsystem, category: "connectionVerifier")
    static let xpcDelegate = Logger(subsystem: subsystem, category: "xpcDelegate")
}
