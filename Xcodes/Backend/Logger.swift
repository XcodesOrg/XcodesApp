import Foundation
import os.log

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!

    static let appState = Logger(subsystem: subsystem, category: "appState")
    static let helperInstaller = Logger(subsystem: subsystem, category: "helperInstaller")
    static let subprocess = Logger(subsystem: subsystem, category: "subprocess")
}
