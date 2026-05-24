import Foundation

public struct XcodeUpdatePolicy: Sendable {
    public static let defaultMaximumCacheAge = TimeInterval(60 * 60 * 5)

    private let maximumCacheAge: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        maximumCacheAge: TimeInterval = Self.defaultMaximumCacheAge,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.maximumCacheAge = maximumCacheAge
        self.now = now
    }

    public func shouldUpdate(
        cachedXcodes: [AvailableXcode],
        lastUpdated: Date?
    ) -> Bool {
        guard cachedXcodes.isEmpty == false, let lastUpdated else {
            return true
        }

        return lastUpdated < now().addingTimeInterval(-maximumCacheAge)
    }
}
