import DockProgress
import Foundation
import Version
import RhodonKit

extension AppState {
    internal func setupDockProgress() {
        DockProgress.progressInstance = nil
        DockProgress.style = .bar

        let progress = Progress(totalUnitCount: AppState.totalProgressUnits)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        overallProgress = progress

        DockProgress.progressInstance = overallProgress
    }

    internal func resetDockProgressTracking() {
        DockProgress
            .progress = 1 // Only way to completely remove overlay with DockProgress is setting progress to complete
    }

    internal func setInstallationStep(of version: Version, to step: XcodeInstallationStep) {
        guard let index = self.allRhodon.firstIndex(where: { $0.version.isEquivalent(to: version) }) else { return }
        self.allRhodon[index].installState = .installing(step)

        let xcode = self.allRhodon[index]
        current.notificationManager.scheduleNotification(
            title: xcode.version.major.description + "." + xcode.version.appleDescription,
            body: step.description,
            category: .normal
        )
    }

    internal func setInstallationStep(
        of runtime: DownloadableRuntime,
        to step: RuntimeInstallationStep,
        postNotification: Bool = true
    ) {
        guard let index = self.downloadableRuntimes.firstIndex(where: { $0.identifier == runtime.identifier })
        else { return }
        self.downloadableRuntimes[index].installState = .installing(step)
        if postNotification {
            current.notificationManager.scheduleNotification(
                title: runtime.name,
                body: step.description,
                category: .normal
            )
        }
    }
}
