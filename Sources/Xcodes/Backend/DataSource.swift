import Foundation

public enum DataSource: String, CaseIterable, Identifiable, CustomStringConvertible, Sendable {
    case apple
    case xcodeReleases
    
    public var id: Self { self }
    
    public static let `default` = DataSource.xcodeReleases
    
    public var description: String {
        switch self {
        case .apple: return "Apple"
        case .xcodeReleases: return "Xcode Releases"
        }
    }

    var isManaged: Bool { PreferenceKey.dataSource.isManaged() }
}
