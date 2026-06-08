import XcodesKit

public typealias Downloader = XcodeArchiveDownloader

extension Downloader {
    var isManaged: Bool { PreferenceKey.downloader.isManaged() }
}
