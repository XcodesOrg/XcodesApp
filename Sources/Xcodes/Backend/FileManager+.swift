import Foundation

extension FileManager {
    /**
     Moves an item to the trash.
     
     This implementation exists only to make the existing method more idiomatic by returning the resulting URL instead of setting the value on an inout argument.

     FB6735133: FileManager.trashItem(at:resultingItemURL:) is not an idiomatic Swift API
     */
    @discardableResult
    func trashItem(at url: URL) throws -> URL {
        var resultingItemURL: NSURL!
        if fileExists(atPath: url.path) {
            try trashItem(at: url, resultingItemURL: &resultingItemURL)
        } else {
            throw FileError.fileNotFound(url.lastPathComponent)
        }
        return resultingItemURL as URL
    }
}
