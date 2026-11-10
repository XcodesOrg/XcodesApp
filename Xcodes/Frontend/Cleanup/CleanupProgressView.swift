import SwiftUI

/// Closing the window only hides this view; CleanupModel owns the running batch.
struct CleanupProgressView: View {
    let progress: CleanupProgress
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressView().controlSize(.small)
                Text(progress.statusText).monospacedDigit()
                Spacer()
                Button(progress.stopRequested ? "Stopping…" : "Stop", action: stop)
                    .disabled(progress.stopRequested)
            }
            if let name = progress.currentName {
                Text(name).lineLimit(1).truncationMode(.middle)
                    .help(progress.currentPath ?? name)
                if let path = progress.currentPath {
                    Text(path).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            ProgressView(value: Double(progress.completedCount), total: Double(max(progress.totalCount, 1)))
                .accessibilityLabel("Cleanup progress")
                .accessibilityValue("\(progress.completedCount) of \(progress.totalCount) processed")
            Text("Closing this window keeps cleanup running.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
