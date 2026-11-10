import Darwin
import Foundation
import XcodesCleanupKit

/// App-owned scan lifecycle, cancellation, and coalesced progress delivery.
extension CleanupModel {
    /// Called by the main window once; the scan belongs to the app, not a window.
    func start(appState: AppState) {
        self.appState = appState
        guard !hasStarted else { return }
        hasStarted = true
        if !isScanning && !isCleaning && (foldersNeedScan || result?.progress.phase != .completed) { scan() }
    }

    func open(appState: AppState) {
        self.appState = appState
        cleanupWindowOpen = true
        guard !isScanning, !isCleaning else { return }
        if foldersNeedScan || result?.progress.phase != .completed {
            scan()
        } else {
            activityTask?.cancel()
            activityTask = Task { [weak self] in await self?.refreshActivity() }
            updateEstimate()
        }
    }

    func close() {
        cleanupWindowOpen = false
        estimateTask?.cancel(); estimateTask = nil
        isEstimating = false
    }

    private func stopScan() {
        generation = UUID()
        session?.cancel(); session = nil
        scanTask?.cancel(); scanTask = nil
        estimateTask?.cancel(); estimateTask = nil
        activityTask?.cancel(); activityTask = nil
        simulatorNamesTask?.cancel(); simulatorNamesTask = nil
        osMetadataTask?.cancel(); osMetadataTask = nil
        // Confirmed cleanup batches continue to report their individual outcomes.
        isScanning = false
        isEstimating = false
    }

    func cancelScan() {
        stopScan()
    }

    /// Refresh in the background while retaining the last completed estimate for display.
    func scan() {
        guard !isCleaning else { return }
        do { try reloadFolderConfiguration() }
        catch { message = "Could not load cleanup-folders.json: " + error.localizedDescription; return }
        stopScan()
        cleanupNoticeTask?.cancel(); cleanupNoticeTask = nil; cleanupProgress = nil
        foldersNeedScan = false
        cleanedItems = []; cleanedBytes = [:]; cleanedRuntimes = []
        selected = []; selectedRuntimes = []; osVersions = [:]; attemptedOSMetadata = []; estimate = nil; progress = nil; message = nil
        isScanning = true
        activityUnavailable = true
        simulatorAssessment = nil
        attemptedSimulatorNames = []
        activityTask = Task { [weak self] in await self?.refreshActivity() }
        let token = generation
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.configureScan(categories: try self.makeCatalog(), policyCategories: try self.makeCatalog(includeAllPolicies: true))
                let userRoots = Set(try self.folders.map { try FilesystemPath($0.url) })
                let roots = self.catalog.map(\.location).filter { path in
                    // Keep explicitly added roots so missing or denied folders remain visible.
                    if userRoots.contains(path) { return true }
                    var metadata = stat()
                    let status = path.bytes.withUnsafeBufferPointer { bytes in
                        let terminated = Array(bytes) + [0]
                        return terminated.withUnsafeBytes { lstat($0.baseAddress!.assumingMemoryBound(to: CChar.self), &metadata) }
                    }
                    return status == 0 || errno != ENOENT
                }
                try Task.checkCancellation()
                guard !roots.isEmpty else {
                    self.result = nil; self.progress = nil; self.findings = []; self.sections = []; self.visibleSections = []
                    self.isScanning = false; self.applyOSFilter()
                    self.isShowingCachedResults = false; self.cachedScannedBytes = 0
                    self.lastScanCompletedAt = Date()
                    self.availableCleanupBytes = 0
                    self.refreshAvailableCleanupBytes()
                    return
                }
                let limits = self.scanDepth == 0 ? [:] : Dictionary(uniqueKeysWithValues:
                    userRoots.filter { roots.contains($0) }.map { ($0, self.scanDepth) })
                let session = try ScanSession(request: ScanRequest(roots: roots, categories: self.catalog,
                    detectNodeModules: true, rootDepthLimits: limits))
                self.session = session
                for await snapshot in session.snapshots {
                    guard self.generation == token, !Task.isCancelled else { session.cancel(); return }
                    // Progress is coalesced by the scanner. Materialize a queryable view
                    // so completed top-level folders are available before the whole scan ends.
                    self.receiveScanProgress(snapshot.result ?? session.currentResult())
                }
                let result = try await session.result()
                guard self.generation == token, !Task.isCancelled else { return }
                self.finishScan(result)
            } catch is CancellationError {
                if self.generation == token { self.isScanning = false }
            } catch {
                if self.generation == token { self.isScanning = false; self.message = error.localizedDescription }
            }
        }
    }

    func receiveScanProgress(_ result: ScanResult) {
        if self.result?.scanID != result.scanID { cleanedItems = []; cleanedBytes = [:] }
        isShowingCachedResults = false; cachedScannedBytes = 0; cachedItemBytes = [:]
        self.result = result
        findings = result.findings
        progress = result.progress
        classificationCache.removeAll(keepingCapacity: true)
        classificationPolicy = CleanupPolicy(categories: policyCatalog, findings: result.findings)
        rebuildSections()
        applyOSFilter()
        resolveOSMetadata()
        resolveUnknownSimulatorNames()
    }

    func configureScan(categories: [FindingCategory], policyCategories: [FindingCategory]) {
        catalog = categories
        hasConfiguredScope = true
        policyCatalog = policyCategories
        classificationPolicy = CleanupPolicy(categories: policyCategories, findings: findings)
        protectedPaths = Self.makeProtectedPaths()
        classificationCache.removeAll(keepingCapacity: true)
    }

    func finishScan(_ result: ScanResult, completedAt: Date = Date()) {
        lastScanCompletedAt = completedAt
        isScanning = false
        foldersNeedScan = false
        receiveScanProgress(result)
        sections.sort {
            if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
            return $0.title == $1.title ? $0.id < $1.id : $0.title < $1.title
        }
        applyOSFilter()
        refreshAvailableCleanupBytes()
        session = nil
    }
}
