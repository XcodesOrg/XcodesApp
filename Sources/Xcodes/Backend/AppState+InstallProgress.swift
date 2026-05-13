import DockProgress
import Foundation
import Version
import XcodesKit

extension AppState {
    internal func setupDockProgress() {
        Task { @MainActor in
            DockProgress.progressInstance = nil
            DockProgress.style = .bar

            let progress = Progress(totalUnitCount: AppState.totalProgressUnits)
            progress.kind = .file
            progress.fileOperationKind = .downloading
            overallProgress = progress

            DockProgress.progressInstance = overallProgress
        }
    }

    internal func resetDockProgressTracking() {
        Task { @MainActor in
            DockProgress
                .progress = 1 // Only way to completely remove overlay with DockProgress is setting progress to complete
        }
    }

    internal func setInstallationStep(of version: Version, to step: XcodeInstallationStep) {
        DispatchQueue.main.async {
            guard let index = self.allXcodes.firstIndex(where: { $0.version.isEquivalent(to: version) }) else { return }
            self.allXcodes[index].installState = .installing(step)

            let xcode = self.allXcodes[index]
            current.notificationManager.scheduleNotification(
                title: xcode.version.major.description + "." + xcode.version.appleDescription,
                body: step.description,
                category: .normal
            )
        }
    }

    internal func setInstallationStep(
        of runtime: DownloadableRuntime,
        to step: RuntimeInstallationStep,
        postNotification: Bool = true
    ) {
        DispatchQueue.main.async {
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
}
