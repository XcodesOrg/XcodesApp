import Foundation
import Version

public struct XcodeListStore: Sendable {
    public typealias FetchAvailableXcodes = @Sendable (XcodeListDataSource) async throws -> [AvailableXcodeRelease]
    public typealias Now = @Sendable () -> Date

    public private(set) var availableXcodes: [AvailableXcode]
    public private(set) var lastUpdated: Date?

    private var cache: AvailableXcodeCache
    private var fetchAvailableXcodes: FetchAvailableXcodes
    private var updatePolicy: XcodeUpdatePolicy
    private var now: Now

    public init(
        availableXcodes: [AvailableXcode] = [],
        lastUpdated: Date? = nil,
        cache: AvailableXcodeCache,
        fetchAvailableXcodes: @escaping FetchAvailableXcodes,
        updatePolicy: XcodeUpdatePolicy = XcodeUpdatePolicy(),
        now: @escaping Now = { Date() }
    ) {
        self.availableXcodes = availableXcodes
        self.lastUpdated = lastUpdated
        self.cache = cache
        self.fetchAvailableXcodes = fetchAvailableXcodes
        self.updatePolicy = updatePolicy
        self.now = now
    }

    public init(
        availableXcodes: [AvailableXcode] = [],
        lastUpdated: Date? = nil,
        cache: AvailableXcodeCache,
        service: XcodeListService,
        updatePolicy: XcodeUpdatePolicy = XcodeUpdatePolicy(),
        now: @escaping Now = { Date() }
    ) {
        self.init(
            availableXcodes: availableXcodes,
            lastUpdated: lastUpdated,
            cache: cache,
            fetchAvailableXcodes: { dataSource in
                try await service.availableXcodes(from: dataSource)
            },
            updatePolicy: updatePolicy,
            now: now
        )
    }

    public var shouldUpdateBeforeListingVersions: Bool {
        updatePolicy.shouldUpdate(
            cachedXcodes: availableXcodes,
            lastUpdated: lastUpdated
        )
    }

    public func shouldUpdateBeforeDownloading(version: Version) -> Bool {
        availableXcodes.first(withVersion: version) == nil
    }

    public mutating func loadCachedAvailableXcodes() throws {
        guard let xcodes = try cache.load() else { return }

        availableXcodes = xcodes
        lastUpdated = cache.lastModified()
    }

    @discardableResult
    public mutating func updateAvailableXcodes(from dataSource: XcodeListDataSource) async throws -> [AvailableXcode] {
        let releases = try await fetchAvailableXcodes(dataSource)
        let xcodes = Self.postprocess(releases.map(AvailableXcode.init))

        availableXcodes = xcodes
        lastUpdated = now()
        try? cache.save(xcodes)
        return xcodes
    }

    public func saveAvailableXcodes(_ xcodes: [AvailableXcode]) throws {
        try cache.save(xcodes)
    }

    public static func postprocess(_ xcodes: [AvailableXcode]) -> [AvailableXcode] {
        XcodeListService.filteringPrereleasesWithDuplicateBuildMetadata(xcodes)
    }
}
