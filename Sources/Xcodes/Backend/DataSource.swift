import Foundation

public enum DataSource: String, CaseIterable, Identifiable, CustomStringConvertible {
    case apple
    case xcodeReleases
    
    public var id: Self { self }
    
    public static var `default` = DataSource.xcodeReleases
    
    public var description: String {
        switch self {
        case .apple: return "Apple"
        case .xcodeReleases: return "Xcode Releases"
        }
    }

    var isManaged: Bool { PreferenceKey.dataSource.isManaged() }
}
