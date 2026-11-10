import SwiftUI
import XcodesKit

struct InstallationStepRowView: View {
    let installationStep: XcodeInstallationStep
    let cancel: () -> Void

    var body: some View {
        Button(action: cancel) {
            switch installationStep {
            case let .downloading(progress):
                // FB8955769 ProgressView.init(_: Progress) doesn't ensure that changes from the Progress object are applied to the UI on the main thread
                // This Progress is vended by URLSession so I don't think we can control that.
                // Use our own version of ProgressView that does this instead.
                DownloadProgressRing(progress, installationStep: installationStep)
            case .authenticating, .unarchiving, .moving, .trashingArchive, .checkingSecurity, .finishing:
                InstallProgressRing(fractionCompleted: nil)
                    .help(installationStep.stepDescription())
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text("StopInstallation"))
        .accessibilityValue(Text(installationStep.stepDescription()))
        .frame(minWidth: 65)
    }
}

private struct DownloadProgressRing: View {
    let installationStep: XcodeInstallationStep
    @StateObject private var progress: ObservingProgressIndicator.ProgressWrapper

    init(_ progress: Progress, installationStep: XcodeInstallationStep) {
        _progress = StateObject(wrappedValue: ObservingProgressIndicator.ProgressWrapper(progress: progress))
        self.installationStep = installationStep
    }

    var body: some View {
        InstallProgressRing(
            fractionCompleted: progress.progress.isIndeterminate ? nil : progress.progress.fractionCompleted
        )
        .help(helpText)
    }

    private var helpText: String {
        let percent = progress.progress.fractionCompleted.formatted(.percent.precision(.fractionLength(0)))
        let stepDescription = installationStep.stepDescription(message: "\(installationStep.message) (\(percent))")
        let details = progress.progress.xcodesLocalizedDescription

        return details.isEmpty ? stepDescription : "\(stepDescription)\n\(details)"
    }
}

struct InstallProgressRing: View {
    @SwiftUI.Environment(\.backgroundProminence) private var backgroundProminence
    let fractionCompleted: Double?
    var showsStopGlyph = true

    private let lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            ring
                .stroke(trackColor, lineWidth: lineWidth)

            if let fractionCompleted {
                ring
                    .trim(from: 0, to: fractionCompleted)
                    .stroke(tintColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: fractionCompleted)
            } else {
                TimelineView(.animation) { context in
                    ring
                        .trim(from: 0, to: 0.3)
                        .stroke(tintColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
                }
            }

            if showsStopGlyph {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tintColor)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 20, height: 20)
        .contentShape(Circle())
    }

    private var ring: some Shape {
        Circle().inset(by: lineWidth / 2)
    }

    private var tintColor: Color {
        backgroundProminence == .increased ? .white : .accentColor
    }

    private var trackColor: Color {
        backgroundProminence == .increased ? .white.opacity(0.35) : .secondary.opacity(0.3)
    }
}

private extension XcodeInstallationStep {
    func stepDescription(message: String? = nil) -> String {
        String(format: localizeString("InstallationStepDescription"), stepNumber, stepCount, message ?? self.message)
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
                        cancel: {}
                    )

                    InstallationStepRowView(
                        installationStep: .unarchiving,
                        cancel: {}
                    )

                    InstallationStepRowView(
                        installationStep: .moving(destination: "/Applications"),
                        cancel: {}
                    )

                    InstallationStepRowView(
                        installationStep: .trashingArchive,
                        cancel: {}
                    )

                    InstallationStepRowView(
                        installationStep: .checkingSecurity,
                        cancel: {}
                    )

                    InstallationStepRowView(
                        installationStep: .finishing,
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
                        cancel: {}
                    )
                }
                .padding()
                .background(Color(.selectedContentBackgroundColor))
                .environment(\.backgroundProminence, .increased)
                .environment(\.colorScheme, colorScheme)
            }
        }
    }
}
