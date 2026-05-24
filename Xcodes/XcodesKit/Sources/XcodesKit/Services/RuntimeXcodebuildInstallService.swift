import Foundation

public struct RuntimeXcodebuildInstallService: Sendable {
    public typealias Download = @Sendable (String, String, String?) -> AsyncThrowingStream<Progress, Error>
    public typealias ProgressChanged = @Sendable (Progress) -> Void

    private let download: Download

    public init(
        download: @escaping Download = { platform, buildVersion, architecture in
            XcodebuildRuntimeDownloadService().download(
                platform: platform,
                buildVersion: buildVersion,
                architecture: architecture
            )
        }
    ) {
        self.download = download
    }

    public func downloadAndInstall(
        runtime: DownloadableRuntime,
        architecture: String? = nil,
        progressChanged: ProgressChanged
    ) async throws {
        let stream = download(
            runtime.platform.shortName,
            runtime.simulatorVersion.buildUpdate,
            architecture
        )

        for try await progress in stream {
            try Task.checkCancellation()
            progressChanged(progress)
        }
        try Task.checkCancellation()
    }
}
