import SwiftUI
import XcodesCleanupKit

struct CleanupItemRow: View {
    @ObservedObject var model: CleanupModel
    let item: ScanItem
    let classification: CleanupClassification

    private var unavailableReason: String? { model.selectionUnavailableReason(item, classification: classification) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { model.selected.contains(item.id) },
                    set: { model.setSelected(item, selected: $0) }
                )) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label(model.displayName(item), systemImage: item.kind == .directory ? "folder" : "doc")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let os = model.operatingSystemLabel(item) {
                            Text(os).font(.caption).foregroundStyle(.secondary).fixedSize()
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(model.isCleaning || unavailableReason != nil)
                .help(unavailableReason ?? "Select for cleanup")
                Spacer(minLength: 12)
                if let unavailableReason, !model.isScanning {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .help(unavailableReason)
                        .accessibilityLabel(unavailableReason)
                }
                Text(item.status == .depthLimited ? "Not scanned (depth limit)" : CleanupSectionData.sizeLabel(bytes: model.displayedBytes(for: item), incomplete: item.status != .complete && item.status != .scanning))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.path.url]) } label: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal \(model.displayName(item)) in Finder")
            }
            if item.isAccessDenied {
                CleanupAccessHelp().padding(.leading, 22)
            }
        }
        .padding(.vertical, 8)
    }
}
