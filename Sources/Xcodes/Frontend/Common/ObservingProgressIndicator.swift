import Combine
import SwiftUI

/// A ProgressIndicator that reflects the state of a Progress object.
/// This functionality is already built in to ProgressView, 
/// but this implementation ensures that changes are received on the main thread.
@available(iOS 14.0, macOS 11.0, *)
public struct ObservingProgressIndicator: View {
    let controlSize: NSControl.ControlSize
    let style: NSProgressIndicator.Style
    let showsAdditionalDescription: Bool
    @StateObject private var progress: ProgressWrapper
    
    public init(
        _ progress: Progress,
        controlSize: NSControl.ControlSize,
        style: NSProgressIndicator.Style,
        showsAdditionalDescription: Bool = false
    ) {
        _progress = StateObject(wrappedValue: ProgressWrapper(progress: progress))
        self.controlSize = controlSize
        self.style = style
        self.showsAdditionalDescription = showsAdditionalDescription
    }
    
    class ProgressWrapper: ObservableObject {
        var progress: Progress
        var cancellable: AnyCancellable!
        
        init(progress: Progress) {
            self.progress = progress
            cancellable = progress.publisher(for: \.fractionCompleted)
                .combineLatest(progress.publisher(for: \.localizedAdditionalDescription))
                .combineLatest(progress.publisher(for: \.isIndeterminate))
                .throttle(for: 1.0, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressIndicator(
                minValue: 0.0,
                maxValue: 1.0,
                doubleValue: progress.progress.fractionCompleted, 
                controlSize: controlSize,
                isIndeterminate: progress.progress.isIndeterminate,
                style: style
            )
            .help(String(format: localizeString("DownloadingPercentDescription"), Int((progress.progress.fractionCompleted * 100))))
            
            if showsAdditionalDescription, progress.progress.xcodesLocalizedDescription.isEmpty == false {
                Text(progress.progress.xcodesLocalizedDescription)
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
                    $0.totalUnitCount = 11944848484
                    $0.completedUnitCount = 848444920
                    $0.throughput = 9211681
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
