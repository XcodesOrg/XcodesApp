import AppKit
import SwiftUI

struct CleanupRuntimeSection: View {
    @ObservedObject var model: CleanupModel
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        let runtimes = model.visibleRuntimes
        let eligible = runtimes.filter { model.runtimeSelectionUnavailableReason($0) == nil }
        let selectedCount = eligible.filter { model.selectedRuntimes.contains($0.id) }.count
        let state: NSControl.StateValue = selectedCount == 0 ? .off : selectedCount == eligible.count ? .on : .mixed
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CleanupSelectionCheckbox(state: state,
                    enabled: !model.isCleaning && !model.isScanning && !eligible.isEmpty,
                    label: "Select eligible simulator runtimes", toggle: model.toggleRuntimeSelection)
                    .frame(width: 18, height: 18)
                    .help("Select all eligible runtimes shown by this filter")
                Button { expanded.toggle() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption.bold()).foregroundStyle(.secondary).frame(width: 10)
                        Text(model.simulatorRuntimeCategory?.title ?? "Simulator runtimes").bold().fixedSize(horizontal: true, vertical: false)
                        Text(model.simulatorRuntimeCategory.map { $0.location.displayPath + "/" } ?? "").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        if selectedCount > 0 { Text("\(selectedCount) selected").font(.caption).foregroundStyle(.secondary) }
                        Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: runtimes.reduce(0) { $0 + $1.sizeBytes }), countStyle: .file)).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Hide simulator runtimes" : "Show simulator runtimes")
                .accessibilityLabel("Simulator runtimes, \(expanded ? "expanded" : "collapsed")")
                Button { NSWorkspace.shared.activateFileViewerSelecting(model.simulatorRuntimeCategory.map { [$0.location.url] } ?? []) } label: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .buttonStyle(.plain).disabled(model.simulatorRuntimeCategory == nil).help("Reveal in Finder").accessibilityLabel("Reveal simulator runtimes in Finder")
            }
            .padding(12)
            .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
            .onHover { hovering = $0 }
            if expanded {
                Divider()
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(runtimes) { runtime in CleanupRuntimeItemRow(model: model, runtime: runtime) }
                }
                .padding(.horizontal, 12).padding(.leading, 28)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
    }
}
