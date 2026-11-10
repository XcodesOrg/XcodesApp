import Foundation

/// Stable section identities preserve disclosure state when filters and sizes change.
enum CleanupListSection: Identifiable, Sendable {
    case files(CleanupSectionData)
    case runtimes(UInt64)

    var id: String {
        switch self {
        case .files(let section): section.id
        case .runtimes: "managed:simulatorRuntimes"
        }
    }
    var allocatedBytes: UInt64 {
        switch self {
        case .files(let section): section.allocatedBytes
        case .runtimes(let bytes): bytes
        }
    }
}
