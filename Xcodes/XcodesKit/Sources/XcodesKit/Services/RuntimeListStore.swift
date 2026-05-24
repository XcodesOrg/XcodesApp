import Foundation

public struct RuntimeListStore: Sendable {
    public typealias FetchDownloadableRuntimes = @Sendable () async throws -> DownloadableRuntimesResponse

    public struct UpdateResult: Sendable {
        public let runtimes: [DownloadableRuntime]
        public let sdkToSeedMappings: [SDKToSeedMapping]
    }

    public private(set) var downloadableRuntimes: [DownloadableRuntime]

    private var cache: DownloadableRuntimeCache
    private var fetchDownloadableRuntimes: FetchDownloadableRuntimes

    public init(
        downloadableRuntimes: [DownloadableRuntime] = [],
        cache: DownloadableRuntimeCache,
        fetchDownloadableRuntimes: @escaping FetchDownloadableRuntimes
    ) {
        self.downloadableRuntimes = downloadableRuntimes
        self.cache = cache
        self.fetchDownloadableRuntimes = fetchDownloadableRuntimes
    }

    public init(
        downloadableRuntimes: [DownloadableRuntime] = [],
        cache: DownloadableRuntimeCache,
        service: RuntimeService
    ) {
        self.init(
            downloadableRuntimes: downloadableRuntimes,
            cache: cache,
            fetchDownloadableRuntimes: {
                try await service.downloadableRuntimes()
            }
        )
    }

    public mutating func loadCachedDownloadableRuntimes() throws {
        guard let runtimes = try cache.load() else { return }

        downloadableRuntimes = runtimes
    }

    @discardableResult
    public mutating func updateDownloadableRuntimes() async throws -> [DownloadableRuntime] {
        try await updateDownloadableRuntimeList().runtimes
    }

    @discardableResult
    public mutating func updateDownloadableRuntimeList() async throws -> UpdateResult {
        let response = try await fetchDownloadableRuntimes()
        let runtimes = response.downloadablesWithSDKBuildUpdates()

        downloadableRuntimes = runtimes
        try? cache.save(runtimes)
        return UpdateResult(
            runtimes: runtimes,
            sdkToSeedMappings: response.sdkToSeedMappings
        )
    }

    public func saveDownloadableRuntimes(_ runtimes: [DownloadableRuntime]) throws {
        try cache.save(runtimes)
    }
}
