import SwiftUI

struct InstallationStepDetailView: View {
    let installationStep: InstallationStep
   
    var body: some View {
        VStack {
            switch installationStep {
                case let .downloading(progress):
                    Text("Step \(installationStep.stepNumber) of \(installationStep.stepCount): \(installationStep.message)")
                        .font(.title2)
                    ObservingProgressIndicator(
                        progress,
                        controlSize: .regular,
                        style: .bar,
                        showsAdditionalDescription: true
                    )

                case .unarchiving, .moving, .trashingArchive, .checkingSecurity, .finishing:
                    ProgressView()
                        .scaleEffect(0.5)
            }
        }
        .frame(minWidth: 80)
    }
}

struct InstallDetailView_Previews: PreviewProvider {
    static var previews: some View {
        InstallationStepDetailView(
            installationStep: .downloading(
                progress: configure(Progress(totalUnitCount: 100)) { $0.completedUnitCount = 40; $0.throughput = 9211681; $0.fileCompletedCount = 84844492; $0.fileTotalCount = 11944848484 }
            )
        )
    }
}
