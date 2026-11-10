import Foundation
import XcodesCleanupKit

/// Prepared when the scan changes, not while SwiftUI lays out or expands a category.
struct CleanupSectionData: Identifiable, Sendable, Codable {
    let id: String
    let title: String
    let locations: [URL]
    let allocatedBytes: UInt64
    let items: [ScanItem]
    let explanation: String?
    let incomplete: Bool
    var accessDenied = false
    var osCategory: String? = nil
    static func sizeLabel(bytes: UInt64, incomplete: Bool) -> String {
        if incomplete && bytes == 0 { return "Size unavailable" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
        return incomplete ? size + " (partial)" : size
    }

}
