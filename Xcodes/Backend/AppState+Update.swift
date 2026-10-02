import Foundation
import Path
import XcodesLoginKit
import XcodesKit

extension AppState {
    
    var isReadyForUpdate: Bool {
        XcodeUpdatePolicy(now: { Current.date() }).shouldUpdate(
            cachedXcodes: availableXcodes,
            lastUpdated: Current.defaults.date(forKey: "lastUpdated")
        )
    }
    
    func updateIfNeeded() {
        // Never cancel a full refresh just because the window became active again.
        if isUpdating, updateTaskIsFullRefresh { return }
        guard
            isReadyForUpdate || !hasRefreshedAvailableXcodesThisLaunch
        else {
            updateTask?.cancel()
            let taskID = UUID()
            updateTaskIsFullRefresh = false
            updateTaskID = taskID
            let task = Task { @MainActor in
                defer {
                    if updateTaskID == taskID {
                        updateTask = nil
                        updateTaskID = nil
                    }
                }
                await self.updateInstalledXcodesAsync()
                await self.updateSelectedXcodePathAsync()
            }
            updateTask = task
            return
        }
        update() as Void
    }

    /// Refreshes installed and available Xcodes and runtimes.
    /// - Parameter restartingInFlightUpdate: Cancel a running refresh and start over, e.g. when the
    ///   data source or sign-in state changed and the running refresh would return stale results.
    func update(restartingInFlightUpdate: Bool = false) {
        if isUpdating {
            // A quick installed-only rescan is always superseded; a full refresh only when asked.
            guard restartingInFlightUpdate || !updateTaskIsFullRefresh else { return }
            updateTask?.cancel()
            updateTask = nil
            updateTaskID = nil
        }
        hasRefreshedAvailableXcodesThisLaunch = true
        updateTaskIsFullRefresh = true
        updateDownloadableRuntimes()
        updateInstalledRuntimes()

        let taskID = UUID()
        updateTaskID = taskID
        let task = Task { @MainActor in
            defer {
                if updateTaskID == taskID {
                    updateTask = nil
                    updateTaskID = nil
                }
            }
            do {
                await self.updateInstalledXcodesAsync()
                await self.updateSelectedXcodePathAsync()
                try Task.checkCancellation()
                let xcodes = try await self.updateAvailableXcodes(from: self.dataSource)
                try Task.checkCancellation()
                self.availableXcodes = xcodes
                Current.defaults.setDate(Current.date(), forKey: "lastUpdated")
            } catch is CancellationError {
            } catch {
                // A restarted refresh can surface its cancellation as a URLError instead
                guard !Task.isCancelled else { return }

                if self.dataSource == .apple, Self.isUnauthorizedInstallError(error) || error as? AuthenticationError == .invalidSession {
                    // The Apple data source needs a developer session; ask the user to sign in rather than
                    // showing a raw 401.
                    self.presentedAlert = .unauthenticatedDataSource
                } else if error as? AuthenticationError != .invalidSession {
                    // Prevent setting the app state error if it is an invalid session, we will present the sign in view instead
                    self.error = error
                    self.presentedAlert = .generic(title: localizeString("Alert.Update.Error.Title"), message: error.legibleLocalizedDescription)
                }
            }
        }
        updateTask = task
    }

    /// Selection can change in Terminal while a full catalog refresh is still running.
    func refreshSelectedXcodePath() {
        guard selectedXcodeRefreshTask == nil else { return }
        selectedXcodeRefreshTask = Task { @MainActor in
            defer { selectedXcodeRefreshTask = nil }
            await updateSelectedXcodePathAsync()
        }
    }

    func updateSelectedXcodePathAsync() async {
        do {
            let output = try await Current.shell.xcodeSelectPrintPath()
            if selectedXcodePath != output.out {
                selectedXcodePath = output.out
            }
        } catch {
            // Ignore xcode-select failures
        }
    }

    private func updateAvailableXcodes(from dataSource: DataSource) async throws -> [AvailableXcode] {
        if dataSource == .apple {
            try await signInIfNeededAsync()
            // This checks whether the Apple ID is a valid Apple Developer account.
            try await validateSessionAsync()
        }

        let service = XcodeListService(urlSession: Current.network.session)
        var store = availableXcodeListStore(service: service)
        return try await store.updateAvailableXcodes(from: dataSource)
    }
}

extension AppState {
    // MARK: - Available Xcode Cache

    func loadCachedAvailableXcodes() throws {
        var store = availableXcodeListStore()
        try store.loadCachedAvailableXcodes()
        availableXcodes = store.availableXcodes
    }

    func cacheAvailableXcodes(_ xcodes: [AvailableXcode]) throws {
        try availableXcodeListStore().saveAvailableXcodes(xcodes)
    }

    private func availableXcodeListStore(service: XcodeListService = XcodeListService()) -> XcodeListStore {
        XcodeListStore(
            cache: availableXcodeCache,
            service: service,
            now: { Current.date() }
        )
    }

    private var availableXcodeCache: AvailableXcodeCache {
        AvailableXcodeCache(
            cacheFile: .cacheFile,
            contentsAtPath: { path in Current.files.contents(atPath: path) },
            writeData: { data, url in try Current.files.write(data, to: url) },
            createDirectory: { url, createIntermediates, attributes in
                try Current.files.createDirectory(
                    at: url,
                    withIntermediateDirectories: createIntermediates,
                    attributes: attributes
                )
            }
        )
    }
    
    // MARK: Runtime Cache
    
    func loadCacheDownloadableRuntimes() throws {
        var store = runtimeListStore
        try store.loadCachedDownloadableRuntimes()
        downloadableRuntimes = store.downloadableRuntimes
    }
    
    func cacheDownloadableRuntimes(_ runtimes: [DownloadableRuntime]) throws {
        try runtimeListStore.saveDownloadableRuntimes(runtimes)
    }

    var runtimeListStore: RuntimeListStore {
        RuntimeListStore(
            cache: downloadableRuntimeCache,
            service: runtimeService
        )
    }

    private var downloadableRuntimeCache: DownloadableRuntimeCache {
        DownloadableRuntimeCache(
            cacheFile: .runtimeCacheFile,
            contentsAtPath: { path in Current.files.contents(atPath: path) },
            writeData: { data, url in try Current.files.write(data, to: url) },
            createDirectory: { url, createIntermediates, attributes in
                try Current.files.createDirectory(
                    at: url,
                    withIntermediateDirectories: createIntermediates,
                    attributes: attributes
                )
            }
        )
    }
}
