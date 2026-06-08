import XcodesKit

public typealias DataSource = XcodesKit.DataSource

extension DataSource {
    var isManaged: Bool { PreferenceKey.dataSource.isManaged() }
}
