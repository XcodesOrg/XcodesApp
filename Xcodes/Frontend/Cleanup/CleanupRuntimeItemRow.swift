import SwiftUI

struct CleanupRuntimeItemRow: View {
    @ObservedObject var model: CleanupModel
    let runtime: CleanupOperations.SimulatorRuntime

    var body: some View {
        let unavailable = model.runtimeSelectionUnavailableReason(runtime)
        return HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { model.selectedRuntimes.contains(runtime.id) },
                                 set: { model.setRuntimeSelected(runtime, selected: $0) })) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(runtime.name, systemImage: "shippingbox")
                    Text(runtime.build).font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(model.isCleaning || unavailable != nil)
            .help(unavailable ?? "Select runtime for removal")
            Spacer(minLength: 12)
            if let unavailable, !model.isScanning {
                Image(systemName: "lock.fill").foregroundStyle(.secondary).help(unavailable).accessibilityLabel(unavailable)
            }
            Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: runtime.sizeBytes), countStyle: .file))
                .monospacedDigit().foregroundStyle(.secondary)
                .help("Size reported by CoreSimulator; reclaimed space may differ.")
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: runtime.runtimeBundlePath ?? runtime.path)]) } label: {
                Image(systemName: "arrow.right.circle.fill")
            }
            .buttonStyle(.plain).help("Reveal in Finder").accessibilityLabel("Reveal \(runtime.name) in Finder")
        }
        .padding(.vertical, 8)
    }
}
