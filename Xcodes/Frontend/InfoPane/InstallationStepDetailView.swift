import SwiftUI

struct InstallationStepDetailView: View {
    let installationStep: InstallationStep
   
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(format: localizeString("InstallationStepDescription"), installationStep.stepNumber, installationStep.stepCount, installationStep.message))

            switch installationStep {
                case let .downloading(progress):
                    ObservingProgressIndicator(
                        progress,
                        controlSize: .regular,
                        style: .bar,
                        showsAdditionalDescription: true
                    )

                case .unarchiving, .moving, .trashingArchive, .checkingSecurity, .finishing:
                    ProgressView()
                        .accessibilityElement(children: .ignore)
                        .scaleEffect(0.5)
            }
        }
    }
}

struct InstallDetailView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            InstallationStepDetailView(
                installationStep: .downloading(
                    progress: configure(Progress()) {
                        $0.kind = .file
                        $0.fileOperationKind = .downloading
                        $0.estimatedTimeRemaining = 123
                        $0.totalUnitCount = 11944848484
                        $0.completedUnitCount = 848444920
                        $0.throughput = 9211681
                    }
                )
            )
            
            InstallationStepDetailView(
                installationStep: .unarchiving
            )
        }
    }
}
