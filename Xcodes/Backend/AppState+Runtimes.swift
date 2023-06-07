import Foundation
import XcodesKit
import OSLog

extension AppState {
    func updateDownloadableRuntimes() {
        Task {
            do {
                let runtimes = try await self.runtimeService.downloadableRuntimes().downloadables
                DispatchQueue.main.async {
                    self.downloadableRuntimes = runtimes
                }
                try? cacheDownloadableRuntimes(runtimes)
            } catch {
                Logger.appState.error("Error downloading runtimes: \(error.localizedDescription)")
            }
        }
    }
    
    func updateInstalledRuntimes() {
        Task {
            do {
                let runtimes = try await self.runtimeService.localInstalledRuntimes()
                DispatchQueue.main.async {
                    self.installedRuntimes = runtimes
                }
            } catch {
                Logger.appState.error("Error loading installed runtimes: \(error.localizedDescription)")
            }
        }
    }
}
