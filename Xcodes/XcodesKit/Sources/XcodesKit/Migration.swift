import Path

/// Migrates any application support files from Xcodes < v0.4 if application support files from >= v0.4 don't exist
public func migrateApplicationSupportFiles() {
    if Current.files.fileExistsAtPath(Path.oldXcodesApplicationSupport.string) {
        if Current.files.fileExistsAtPath(Path.xcodesApplicationSupport.string) {
            Current.logging.log("Removing old support files...")
            try? Current.files.removeItem(Path.oldXcodesApplicationSupport.url)
            Current.logging.log("Done")
        }
        else {
            Current.logging.log("Migrating old support files...")
            try? Current.files.moveItem(Path.oldXcodesApplicationSupport.url, Path.xcodesApplicationSupport.url)
            Current.logging.log("Done")
        }
    }
}
