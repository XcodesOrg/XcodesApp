import AppKit
import SwiftUI
import XcodesCleanupKit

struct CleanupWindow: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var model: CleanupModel
    @SwiftUI.Environment(\.dismissWindow) private var dismissWindow
    @State private var confirmingCleanup = false
    @State private var showingSavingsHelp = false
    @State private var showingFolders = false
    @State private var confirmedAssociations: [String: Set<CleanupOperations.SimulatorXcode>] = [:]

    var body: some View {
        let sections = model.listSections
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clean Up").font(.title)
                    Text("Review developer storage and choose what to clean.").foregroundStyle(.secondary)
                    if let completedAt = model.lastScanCompletedAt {
                        Text("Last scan: \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.isShowingCachedResults {
                        Text("Showing cached results")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if model.isScanning && model.availableCleanupBytes != nil {
                        Text("Showing last completed estimate while refreshing")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let bytes = model.availableCleanupBytes {
                        Text("~\(ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file))")
                            .font(.title2).monospacedDigit()
                    } else {
                        Text("—").font(.title2)
                    }
                    Text("Available to clean up").font(.caption).foregroundStyle(.secondary)
                    Text("Total scanned: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: model.totalScannedBytes), countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    HStack(spacing: 6) {
                        if model.isScanning {
                            ProgressView().controlSize(.mini)
                            Text("Scanning \(model.progress?.scannedFileCount ?? 0) files…")
                                .monospacedDigit()
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .help("Estimated storage eligible for cleanup across all OS versions, matching the main window. Shared APFS storage may reduce actual savings. Total scanned also includes storage requiring external management and incomplete results.")
                if model.isScanning {
                    Button("Cancel", action: model.cancelScan).controlSize(.large)
                } else if model.isCleaning {
                    Button("Close Window") { dismissWindow(id: "cleanup") }
                        .controlSize(.large)
                        .help("Cleanup continues in the background")
                } else {
                    Button("Rescan", action: model.scan).controlSize(.large).buttonStyle(.borderedProminent)
                        .disabled(model.isCleaning)
                }
            }
            HStack {
                Button("Folders…") { showingFolders = true }.disabled(model.isCleaning)
                if model.runtimeInventoryUnavailable && !model.isScanning {
                    Text("Runtime inventory unavailable").font(.caption).foregroundStyle(.secondary)
                        .help("Rescan to retry CoreSimulator's runtime inventory.")
                }
                Spacer()
                Picker("Operating system", selection: $model.selectedOperatingSystem) {
                    Text("All OS versions").tag(String?.none)
                    ForEach(model.operatingSystems, id: \.self) { os in Text(os).tag(Optional(os)) }
                    if let selected = model.selectedOperatingSystem, !model.operatingSystems.contains(selected) {
                        Text(selected).tag(Optional(selected))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(model.isCleaning)
                .help("Filter by OS major version. Changing the filter clears your selection.")
            }
            if let progress = model.cleanupProgress, model.isCleaning {
                CleanupProgressView(progress: progress, stop: model.stopCleanupAfterCurrentItem)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if sections.isEmpty && !model.isScanning {
                        Text(model.selectedOperatingSystem == nil ? "No cleanup findings. Add a folder to scan." : "No items match this OS version.").foregroundStyle(.secondary)
                    }
                    ForEach(sections) { entry in
                        switch entry {
                        case .files(let section):
                            CleanupCategorySection(model: model,
                                title: section.title,
                                locations: section.locations,
                                allocatedBytes: section.allocatedBytes,
                                items: section.items,
                                explanation: section.explanation,
                                incomplete: section.incomplete,
                                accessDenied: section.accessDenied)
                        case .runtimes:
                            CleanupRuntimeSection(model: model)
                        }
                    }
                }
            }
            Divider()
            HStack {
                if model.isEstimating {
                    Text("Estimating savings from \(model.selectedCount) selected…")
                } else if model.estimate != nil || !model.selectedRuntimes.isEmpty {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(clamping: model.estimatedSavingsBytes), countStyle: .file)) estimated savings from \(model.selectedCount) selected")
                        .monospacedDigit()
                } else {
                    Text("\(model.selectedCount) selected").foregroundStyle(.secondary)
                }
                Button { showingSavingsHelp.toggle() } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .help("About estimated savings")
                .accessibilityLabel("About estimated savings")
                .popover(isPresented: $showingSavingsHelp) { savingsHelp }
                Spacer()
                Button(model.isCleaning ? (model.cleanupIncludesDevices || !model.selectedRuntimes.isEmpty ? "Cleaning…" : "Moving…") : model.cleanupActionTitle) {
                    confirmedAssociations = model.selectedSimulatorAssociations
                    confirmingCleanup = true
                }
                    .disabled(model.selectedCount == 0 || model.isScanning || model.isCleaning)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 600)
        .task { model.open(appState: appState) }
        .onDisappear { model.close() }
        .sheet(isPresented: $showingFolders) { CleanupFoldersView(model: model) }
        .onChange(of: model.selected) { model.updateEstimate() }
        .onChange(of: model.selectedRuntimes) { model.updateEstimate() }
        .confirmationDialog(model.cleanupActionTitle + "?", isPresented: $confirmingCleanup, titleVisibility: .visible) {
            Button(model.cleanupActionTitle, role: .destructive) { model.cleanSelected(confirmedAssociations: confirmedAssociations) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(model.cleanupConfirmationMessage)
        }
        .alert("Cleanup", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }

    private var savingsHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estimated Savings").font(.headline)
            Text("Overlapping file selections and shared storage are accounted for together.")
            Text("Runtime estimates use sizes reported by CoreSimulator; sharing and system assets can make actual reclaimed space lower.")
            if let estimate = model.estimate, !estimate.isComplete {
                Text("Some sharing or metadata could not be fully accounted for.")
            }
            if model.estimate?.limitations.contains(.snapshotsMayRetainBlocks) == true {
                Text("APFS snapshots may retain space after deletion.")
            }
            Text("Files moved to Trash occupy space until Trash is emptied.")
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}
