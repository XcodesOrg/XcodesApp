import AppKit
import SwiftUI

/// Access guidance stays with the folder whose size could not be fully measured.
struct CleanupAccessHelp: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Access denied. Allow Xcodes Full Disk Access, then rescan.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Full Disk Access…") {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
                NSWorkspace.shared.open(url)
            }
            .controlSize(.small)
        }
    }
}
