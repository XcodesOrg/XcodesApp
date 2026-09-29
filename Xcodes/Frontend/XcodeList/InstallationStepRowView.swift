import SwiftUI
import XcodesKit

/// A compact, App Store style progress ring for a row: a determinate ring while downloading and a
/// spinning arc for the other steps, with a stop button in the middle. Step details are in the tooltip.
struct InstallationStepRowView: View {
    let installationStep: XcodeInstallationStep
    let highlighted: Bool
    let cancel: () -> Void

    var body: some View {
        Group {
            switch installationStep {
            case let .downloading(progress):
                // FB8955769 ProgressView.init(_: Progress) doesn't ensure that changes from the Progress object are applied to the UI on the main thread
                DownloadProgressRing(progress: progress, highlighted: highlighted, stepDescription: stepDescription, cancel: cancel)
            case .authenticating, .unarchiving, .moving, .trashingArchive, .checkingSecurity, .finishing:
                ProgressRing(fraction: nil, highlighted: highlighted, cancel: cancel)
                    .help(stepDescription)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(stepDescription))
    }

    private var stepDescription: String {
        String(format: localizeString("InstallationStepDescription"), installationStep.stepNumber, installationStep.stepCount, installationStep.message)
    }
}

private struct DownloadProgressRing: View {
    @StateObject private var progress: ObservingProgressIndicator.ProgressWrapper
    let highlighted: Bool
    let stepDescription: String
    let cancel: () -> Void

    init(progress: Progress, highlighted: Bool, stepDescription: String, cancel: @escaping () -> Void) {
        _progress = StateObject(wrappedValue: ObservingProgressIndicator.ProgressWrapper(progress: progress))
        self.highlighted = highlighted
        self.stepDescription = stepDescription
        self.cancel = cancel
    }

    var body: some View {
        let progress = progress.progress
        let percent = String(format: localizeString("DownloadingPercentDescription"), Int(progress.fractionCompleted * 100))
        let details = progress.xcodesLocalizedDescription
        ProgressRing(fraction: progress.isIndeterminate ? nil : progress.fractionCompleted, highlighted: highlighted, cancel: cancel)
            .help([stepDescription, percent, details].filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}

private struct ProgressRing: View {
    /// nil shows an indeterminate spinning arc
    let fraction: Double?
    let highlighted: Bool
    let cancel: () -> Void

    @State private var isHovering = false
    @State private var isSpinning = false

    private let size: CGFloat = 24
    private let lineWidth: CGFloat = 2.5

    var body: some View {
        Button(action: cancel) {
            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: fraction.map { max(0.02, min(1, $0)) } ?? 0.25)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(fraction == nil && isSpinning ? 270 : -90))
                    .animation(fraction == nil ? .linear(duration: 1).repeatForever(autoreverses: false) : .easeOut(duration: 0.3), value: isSpinning)
                    .animation(.easeOut(duration: 0.3), value: fraction)

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isHovering ? ringColor : ringColor.opacity(0.8))
                    .frame(width: 7, height: 7)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onAppear { isSpinning = fraction == nil }
        .onChange(of: fraction == nil) { isSpinning = $0 }
        .accessibilityLabel(Text("StopInstallation"))
    }

    private var ringColor: Color {
        highlighted ? .white : .accentColor
    }

    private var trackColor: Color {
        highlighted ? .white.opacity(0.35) : .secondary.opacity(0.25)
    }
}

struct InstallView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(ColorScheme.allCases, id: \.self) { colorScheme in
                Group {
                    InstallationStepRowView(
                        installationStep: .downloading(
                            progress: configure(Progress(totalUnitCount: 100)) { $0.completedUnitCount = 40 }
                        ),
                        highlighted: false,
                        cancel: {}
                    )
                    
                    InstallationStepRowView(
                        installationStep: .unarchiving,
                        highlighted: false,
                        cancel: {}
                    )
                    
                    InstallationStepRowView(
                        installationStep: .moving(destination: "/Applications"),
                        highlighted: false,
                        cancel: {}
                    )
                    
                    InstallationStepRowView(
                        installationStep: .trashingArchive,
                        highlighted: false,
                        cancel: {}
                    )
                    
                    InstallationStepRowView(
                        installationStep: .checkingSecurity,
                        highlighted: false,
                        cancel: {}
                    )
                    
                    InstallationStepRowView(
                        installationStep: .finishing,
                        highlighted: false,
                        cancel: {}
                    )
                }
                .padding()
                .background(Color(.windowBackgroundColor))
                .environment(\.colorScheme, colorScheme)
            }
            
            ForEach(ColorScheme.allCases, id: \.self) { colorScheme in
                Group {
                    InstallationStepRowView(
                        installationStep: .downloading(
                            progress: configure(Progress(totalUnitCount: 100)) { $0.completedUnitCount = 40 }
                        ),
                        highlighted: true,
                        cancel: {}
                    )
                }
                .padding()
                .background(Color(.selectedContentBackgroundColor))
                .environment(\.colorScheme, colorScheme)
            }
        }
    }
}
