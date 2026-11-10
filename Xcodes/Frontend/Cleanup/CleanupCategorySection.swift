import AppKit
import SwiftUI
import XcodesCleanupKit

struct CleanupCategorySection: View {
    @ObservedObject var model: CleanupModel
    let title: String
    let locations: [URL]
    let allocatedBytes: UInt64
    let items: [ScanItem]
    var explanation: String? = nil
    var incomplete = false
    var accessDenied = false
    @State private var expanded = false
    @State private var hovering = false

    private var eligible: [ScanItem] { model.selectableItems(items) }
    private var selectedCount: Int { items.filter { model.selected.contains($0.id) }.count }
    private var pathLabel: String {
        if locations.count == 1 { return locations[0].path + (locations[0].path.hasSuffix("/") ? "" : "/") }
        return "\(locations.count) locations"
    }

    var body: some View {
        let eligible = self.eligible
        let selectedEligibleCount = eligible.filter { model.selected.contains($0.id) }.count
        let selectionState: NSControl.StateValue = selectedEligibleCount == 0 ? .off : selectedEligibleCount == eligible.count ? .on : .mixed
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CleanupSelectionCheckbox(state: selectionState,
                    enabled: !model.isScanning && !model.isCleaning && !eligible.isEmpty,
                    label: "Select eligible items in \(title)") {
                        model.toggleSelection(items)
                    }
                    .frame(width: 18, height: 18)
                    .help("Select all eligible items in this category")
                Button { expanded.toggle() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text(title).bold().fixedSize(horizontal: true, vertical: false)
                        Text(pathLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        if selectedCount > 0 {
                            Text("\(selectedCount) selected").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(CleanupSectionData.sizeLabel(bytes: allocatedBytes, incomplete: incomplete))
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help((expanded ? "Hide items in " : "Show items in ") + title + "\n" + locations.map(\.path).joined(separator: "\n"))
                .accessibilityLabel("\(title), \(expanded ? "expanded" : "collapsed")")
                Button { NSWorkspace.shared.activateFileViewerSelecting(locations) } label: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(locations.isEmpty)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal \(title) in Finder")

            }
            .padding(12)
            .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
            .onHover { hovering = $0 }
            if accessDenied {
                CleanupAccessHelp()
                    .padding(.horizontal, 12)
                    .padding(.leading, 28)
                    .padding(.bottom, 10)
            }
            if expanded {
                Divider()
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let explanation {
                        Text(explanation).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    if model.isScanning && items.isEmpty {
                        Text("Scanning…").foregroundStyle(.secondary).padding(.vertical, 8)
                    } else {
                        ForEach(items) { item in
                            CleanupItemRow(model: model, item: item, classification: model.classification(for: item))
                        }
                    }
                    if incomplete && !accessDenied {
                        Text(allocatedBytes == 0 ? "This folder could not be read." : "Partial size. Increase the scan depth in Folders or resolve unreadable entries for a complete scan.")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.leading, 28)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
    }
}
