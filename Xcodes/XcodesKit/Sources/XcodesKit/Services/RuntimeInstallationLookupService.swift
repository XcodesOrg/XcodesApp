import Foundation
@preconcurrency import Path

public struct RuntimeInstallationLookupService: Sendable {
    public init() {}

    public func coreSimulatorImage(
        for runtime: DownloadableRuntime,
        in installedRuntimes: [CoreSimulatorImage]
    ) -> CoreSimulatorImage? {
        installedRuntimes.first {
            $0.runtimeInfo.build == runtime.simulatorVersion.buildUpdate &&
                runtimeArchitectureMatches(runtime, installedRuntime: $0)
        }
    }

    public func installPath(
        for runtime: DownloadableRuntime,
        in installedRuntimes: [CoreSimulatorImage]
    ) -> Path? {
        guard
            let image = coreSimulatorImage(for: runtime, in: installedRuntimes),
            let relativePath = image.path["relative"]
        else {
            return nil
        }

        let path = relativePath.replacingOccurrences(of: "file://", with: "")
        return Path(url: URL(fileURLWithPath: path))
    }

    private func runtimeArchitectureMatches(
        _ runtime: DownloadableRuntime,
        installedRuntime: CoreSimulatorImage
    ) -> Bool {
        guard let architectures = runtime.architectures, architectures.isEmpty == false else {
            return true
        }

        return installedRuntime.runtimeInfo.supportedArchitectures == architectures
    }
}
