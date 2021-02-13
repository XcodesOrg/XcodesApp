
import Combine
import SwiftUI

/// A ProgressIndicator that reflects the state of a Progress object.
/// This functionality is already built in to ProgressView,
/// but this implementation ensures that changes are received on the main thread.
@available(iOS 14.0, macOS 11.0, *)
public struct ObservingDownloadStatsView: View {
    let controlSize: NSControl.ControlSize
    let style: NSProgressIndicator.Style
    @StateObject private var progress: ProgressWrapper
    
    public init(
        _ progress: Progress,
        controlSize: NSControl.ControlSize,
        style: NSProgressIndicator.Style
    ) {
        _progress = StateObject(wrappedValue: ProgressWrapper(progress: progress))
        self.controlSize = controlSize
        self.style = style
    }
    
    class ProgressWrapper: ObservableObject {
        var progress: Progress
        var cancellable: AnyCancellable!
        
        init(progress: Progress) {
            self.progress = progress
            cancellable = progress
                .publisher(for: \.completedUnitCount)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
    
    public var body: some View {
        
        VStack{
            ProgressIndicator(
                minValue: 0.0,
                maxValue: 1.0,
                doubleValue: progress.progress.fractionCompleted,
                controlSize: controlSize,
                isIndeterminate: progress.progress.isIndeterminate,
                style: style
            )
            .help("Downloading: \(Int((progress.progress.fractionCompleted * 100)))% complete")
            HStack {
                if let fileCompletedCount = progress.progress.fileCompletedCount, let fileTotalCount = progress.progress.fileTotalCount {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(fileCompletedCount), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(fileTotalCount), countStyle: .file))")
                }
                if let throughput = progress.progress.throughput {
                    Text(" at \(ByteCountFormatter.string(fromByteCount: Int64(throughput), countStyle: .binary))/sec")
                }
            }
        }
        
        
    }
}

@available(iOS 14.0, macOS 11.0, *)
struct ObservingDownloadStats_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ObservingDownloadStatsView(
                configure(Progress(totalUnitCount: 100)) {
                    $0.completedUnitCount = 40
                },
                controlSize: .small,
                style: .spinning
            )
        }
        .previewLayout(.sizeThatFits)
    }
}
