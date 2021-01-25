import SwiftUI

struct InstallationStepView: View {
    let installationStep: InstallationStep
    let highlighted: Bool
    let cancel: () -> Void
    
    var body: some View {
        HStack {
            switch installationStep {
            case let .downloading(progress):
                // FB8955769 ProgressView.init(_: Progress) doesn't ensure that changes from the Progress object are applied to the UI on the main thread
                // This Progress is vended by URLSession so I don't think we can control that.
                // Use our own version of ProgressView that does this instead.
                ObservingProgressIndicator(
                    progress,
                    controlSize: .small,
                    style: .spinning
                )
                .help("Downloading: \(Int((progress.fractionCompleted * 100)))% complete")
            case .unarchiving, .moving, .trashingArchive, .checkingSecurity, .finishing:
                ProgressView()
                    .scaleEffect(0.5)
            }
            
            Text("Step \(installationStep.stepNumber) of \(installationStep.stepCount): \(installationStep.message)")
                .font(.footnote)
            
            Button(action: cancel) {
                Label("Cancel", systemImage: "xmark.circle.fill")
                    .labelStyle(IconOnlyLabelStyle())
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(highlighted ? .white : .secondary)
            .help("Stop installation")
        }
        .frame(minWidth: 80)
    }
}

struct InstallView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(ColorScheme.allCases, id: \.self) { colorScheme in
                Group {
                    InstallationStepView(
                        installationStep: .downloading(
                            progress: configure(Progress(totalUnitCount: 100)) { $0.completedUnitCount = 40 }
                        ),
                        highlighted: false,
                        cancel: {}
                    )
                    
                    InstallationStepView(
                        installationStep: .unarchiving,
                        highlighted: false,
                        cancel: {}
                    )
                    
                    InstallationStepView(
                        installationStep: .moving(destination: "/Applications"),
                        highlighted: false,
                        cancel: {}
                    )
                    
                    InstallationStepView(
                        installationStep: .trashingArchive,
                        highlighted: false,
                        cancel: {}
                    )
                    
                    InstallationStepView(
                        installationStep: .checkingSecurity,
                        highlighted: false,
                        cancel: {}
                    )
                    
                    InstallationStepView(
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
                    InstallationStepView(
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
