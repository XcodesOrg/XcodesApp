import Foundation
import os.log

enum FileOperations {
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let fileOperations = Logger(subsystem: subsystem, category: "fileOperations")

    static func moveApp(at source: String, to destination: String, completion: @escaping ((any Error)?) -> Void) {
        do {
            guard URL(fileURLWithPath: source).hasDirectoryPath else { throw XPCDelegateError(.invalidSourcePath)}

            guard URL(fileURLWithPath: destination).deletingLastPathComponent().hasDirectoryPath else { throw
                XPCDelegateError(.invalidDestinationPath)}

            try FileManager.default.moveItem(at: URL(fileURLWithPath: source), to: URL(fileURLWithPath: destination))
            completion(nil)
        } catch {
            completion(error)
        }
    }

    // does an Xcode.app file exist?
    static func createSymbolicLink(source: String, destination: String, completion: @escaping ((any Error)?) -> Void) {
        do {
            if FileManager.default.fileExists(atPath: destination) {
                let attributes: [FileAttributeKey : Any]? = try? FileManager.default.attributesOfItem(atPath: destination)

                if attributes?[.type] as? FileAttributeType == FileAttributeType.typeSymbolicLink {
                    try FileManager.default.removeItem(atPath: destination)
                    Self.fileOperations.info("Successfully deleted old symlink")
                } else {
                    throw XPCDelegateError(.destinationIsNotASymbolicLink)
                }
            }

            try FileManager.default.createSymbolicLink(atPath: destination, withDestinationPath: source)
            Self.fileOperations.info("Successfully created symbolic link with \(destination)")
            completion(nil)
        } catch {
            completion(error)
        }
    }

    static func rename(source: String, destination: String, completion: @escaping ((any Error)?) -> Void) {
        do {
            try FileManager.default.moveItem(at: URL(fileURLWithPath: source), to: URL(fileURLWithPath: destination))
            completion(nil)
        } catch {
            completion(error)
        }
    }

    static func remove(path: String, completion: @escaping ((any Error)?) -> Void) {
        do {
            try FileManager.default.removeItem(atPath: path)
            completion(nil)
        } catch {
            completion(error)
        }
    }
}
