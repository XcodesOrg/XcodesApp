import Foundation
import XcodesKit

extension FileManager {
    /**
     Moves an item to the trash.
     
     This implementation exists only to make the existing method more idiomatic by returning the resulting URL instead of setting the value on an inout argument.

     FB6735133: FileManager.trashItem(at:resultingItemURL:) is not an idiomatic Swift API
     */
    @discardableResult
    func trashItem(at url: URL) throws -> URL {
        if fileExists(atPath: url.path) {
            return try xcodesTrashItem(at: url)
        } else {
            throw FileError.fileNotFound(url.lastPathComponent)
        }
    }
}
