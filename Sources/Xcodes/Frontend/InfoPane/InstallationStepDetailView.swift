import SwiftUI
import XcodesKit

struct InstallationStepDetailView: View {
    let installationStep: XcodeInstallationStep
   
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

                case .authenticating, .unarchiving, .moving, .trashingArchive, .checkingSecurity, .finishing:
                    ProgressView()
                        .scaleEffect(0.5)
            }
        }
    }
}

#Preview("Downloading") {
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
  .padding()
}

#Preview("Unarchiving") {
    InstallationStepDetailView(
      installationStep: .unarchiving
    )
    .padding()
}
