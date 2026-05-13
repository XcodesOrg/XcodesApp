import Observation
import SwiftUI

/// A ProgressIndicator that reflects the state of a Progress object.
/// This functionality is already built in to ProgressView,
/// but this implementation ensures that changes are received on the main thread.
@available(iOS 14.0, macOS 11.0, *)
public struct ObservingProgressIndicator: View {
    let controlSize: NSControl.ControlSize
    let style: NSProgressIndicator.Style
    let showsAdditionalDescription: Bool
    @State private var progress: ProgressWrapper

    public init(
        _ progress: Progress,
        controlSize: NSControl.ControlSize,
        style: NSProgressIndicator.Style,
        showsAdditionalDescription: Bool = false
    ) {
        _progress = State(wrappedValue: ProgressWrapper(progress: progress))
        self.controlSize = controlSize
        self.style = style
        self.showsAdditionalDescription = showsAdditionalDescription
    }

    @MainActor
    @Observable
    class ProgressWrapper {
        var progress: Progress
        var fractionCompleted = 0.0
        var localizedDescription = ""
        var isIndeterminate = false
        @ObservationIgnored private var observationTask: Task<Void, Never>?

        init(progress: Progress) {
            self.progress = progress
            update()
            observationTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.update()
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }

        deinit {
            observationTask?.cancel()
        }

        private func update() {
            fractionCompleted = progress.fractionCompleted
            localizedDescription = progress.xcodesLocalizedDescription
            isIndeterminate = progress.isIndeterminate
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressIndicator(
                minValue: 0.0,
                maxValue: 1.0,
                doubleValue: progress.fractionCompleted,
                controlSize: controlSize,
                isIndeterminate: progress.isIndeterminate,
                style: style
            )
            .help("Downloading: \(Int(progress.fractionCompleted * 100))% complete")

            if showsAdditionalDescription, progress.localizedDescription.isEmpty == false {
                Text(progress.localizedDescription)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }
}

@available(iOS 14.0, macOS 11.0, *)
struct ObservingProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ObservingProgressIndicator(
                configure(Progress(totalUnitCount: 100)) {
                    $0.completedUnitCount = 40
                },
                controlSize: .small,
                style: .spinning
            )

            ObservingProgressIndicator(
                configure(Progress()) {
                    $0.kind = .file
                    $0.fileOperationKind = .downloading
                    $0.estimatedTimeRemaining = 123
                    $0.totalUnitCount = 11_944_848_484
                    $0.completedUnitCount = 848_444_920
                    $0.throughput = 9_211_681
                },
                controlSize: .regular,
                style: .bar,
                showsAdditionalDescription: true
            )

            ObservingProgressIndicator(
                configure(Progress()) {
                    $0.kind = .file
                    $0.fileOperationKind = .downloading
                    $0.totalUnitCount = 0
                    $0.completedUnitCount = 0
                },
                controlSize: .regular,
                style: .bar,
                showsAdditionalDescription: true
            )
        }
        .previewLayout(.sizeThatFits)
    }
}
