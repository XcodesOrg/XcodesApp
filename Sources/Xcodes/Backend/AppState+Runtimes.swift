import Foundation
import XcodesKit
import OSLog
import Path
import AppleAPI
import Version

extension AppState {
    func updateDownloadableRuntimes() {
        Task {
            do {
                
                let downloadableRuntimes = try await self.runtimeService.downloadableRuntimes()
                let runtimes = downloadableRuntimes.downloadables.map { runtime in
                    var updatedRuntime = runtime
                    
                    // This loops through and matches up the simulatorVersion to the mappings
                    let simulatorBuildUpdate = downloadableRuntimes.sdkToSimulatorMappings.filter { SDKToSimulatorMapping in
                        SDKToSimulatorMapping.simulatorBuildUpdate == runtime.simulatorVersion.buildUpdate
                    }
                    updatedRuntime.sdkBuildUpdate = simulatorBuildUpdate.map { $0.sdkBuildUpdate }
                    return updatedRuntime
                }
    
                Task { @MainActor in
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
                Logger.appState.info("Loading Installed runtimes")
                let runtimes = try await self.runtimeService.localInstalledRuntimes()
                
                Task { @MainActor in
                    self.installedRuntimes = runtimes
                }
            } catch {
                Logger.appState.error("Error loading installed runtimes: \(error.localizedDescription)")
            }
        }
    }
    
    func downloadRuntime(runtime: DownloadableRuntime) {
        guard let selectedXcode = self.allXcodes.first(where: { $0.selected }) else {
            Logger.appState.error("No selected Xcode")
            Task { @MainActor in
                self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: "No selected Xcode. Please make an Xcode active")
            }
            return
        }
        // new runtimes
        if runtime.contentType == .cryptexDiskImage {
            // only selected xcodes > 16.1 beta 3 can download runtimes via a xcodebuild -downloadPlatform version
            // only Runtimes coming from cryptexDiskImage can be downloaded via xcodebuild
            if selectedXcode.version > Version(major: 16, minor: 0, patch: 0) {
                
                if runtime.architectures?.isAppleSilicon ?? false {
                    // Need Xcode 26 but with some RC/Beta's its simpler to just to greater > 25
                    if selectedXcode.version > Version(major: 25, minor: 0, patch: 0) {
                        downloadRuntimeViaXcodeBuild(runtime: runtime)
                    } else {
                        // not supported
                        Logger.appState.error("Trying to download a runtime we can't download")
                        Task { @MainActor in
                            self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: localizeString("Alert.Install.Error.Need.Xcode26"))
                        }
                        return
                    }
                    
                } else {
                    downloadRuntimeViaXcodeBuild(runtime: runtime)
                }
            } else {
                // not supported
                Logger.appState.error("Trying to download a runtime we can't download")
                Task { @MainActor in
                    self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: localizeString("Alert.Install.Error.Need.Xcode16.1"))
                }
                return
            }
        } else {
            downloadRuntimeObseleteWay(runtime: runtime)
        }
    }
    
    func downloadRuntimeViaXcodeBuild(runtime: DownloadableRuntime) {
        
        let downloadRuntimeTask = Current.shell.downloadRuntime(runtime.platform.shortName, runtime.simulatorVersion.buildUpdate, runtime.architectures?.isAppleSilicon ?? false ? Architecture.arm64.rawValue : nil)
        
        runtimePublishers[runtime.identifier] = Task { [weak self] in
            guard let self = self else { return }
            do {
                for try await progress in downloadRuntimeTask {
                    if progress.isIndeterminate {
                        Task { @MainActor in
                            self.setInstallationStep(of: runtime, to: .installing, postNotification: false)
                        }
                    } else {
                        Task { @MainActor in
                            self.setInstallationStep(of: runtime, to: .downloading(progress: progress), postNotification: false)
                        }
                    }
                  
                }
                Logger.appState.debug("Done downloading runtime - \(runtime.name)")
                
                Task { @MainActor in
                    guard let index = self.downloadableRuntimes.firstIndex(where: { $0.identifier == runtime.identifier }) else { return }
                    self.downloadableRuntimes[index].installState = .installed
                    self.update()
                }
                
            } catch {
                    Logger.appState.error("Error downloading runtime: \(error.localizedDescription)")
                    Task { @MainActor in
                        self.error = error
                        self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.legibleLocalizedDescription)
                    }
                }
        }
    }
    
    func downloadRuntimeObseleteWay(runtime: DownloadableRuntime) {
        runtimePublishers[runtime.identifier] = Task {
            do {
                let downloadedURL = try await downloadRunTimeFull(runtime: runtime)
                if !Task.isCancelled {
                    Logger.appState.debug("Installing runtime: \(runtime.name)")
                    Task { @MainActor in
                        self.setInstallationStep(of: runtime, to: .installing)
                    }
                    switch runtime.contentType {
                    case .cryptexDiskImage:
                        // not supported yet (do we need to for old packages?)
                        throw MessageError("Installing via cryptexDiskImage not support - please install manually from \(downloadedURL.description)")
                    case .package:
                        // not supported yet (do we need to for old packages?)
                        throw MessageError("Installing via package not support - please install manually from \(downloadedURL.description)")
                    case .diskImage:
                        try await self.installFromImage(dmgURL: downloadedURL)
                        Task { @MainActor in
                            self.setInstallationStep(of: runtime, to: .trashingArchive)
                        }
                        try Current.files.removeItem(at: downloadedURL)
                    }
                
                    Task { @MainActor in
                        guard let index = self.downloadableRuntimes.firstIndex(where: { $0.identifier == runtime.identifier }) else { return }
                        self.downloadableRuntimes[index].installState = .installed
                    }
                    updateInstalledRuntimes()
                }
              
            }
            catch {
                Logger.appState.error("Error downloading runtime: \(error.localizedDescription)")
                Task { @MainActor in
                    self.error = error
                    self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.legibleLocalizedDescription)
                }
            }
        }
    }
    
    func downloadRunTimeFull(runtime: DownloadableRuntime) async throws -> URL {
        guard let source = runtime.source else {
            throw MessageError("Invalid runtime source")
        }
        
        guard let downloadPath = runtime.downloadPath else {
            throw MessageError("Invalid runtime downloadPath")
        }
    
        // sets a proper cookie for runtimes
        try await authenticationStore.validateADCSession(path: downloadPath)
        
        let downloader = Downloader(rawValue: Current.defaults.string(forKey: "downloader") ?? "aria2") ?? .aria2
        
        let url = URL(string: source)!
        let expectedRuntimePath = Path.xcodesApplicationSupport/"\(url.lastPathComponent)"
        // aria2 downloads directly to the destination (instead of into /tmp first) so we need to make sure that the download isn't incomplete
        let aria2DownloadMetadataPath = expectedRuntimePath.parent/(expectedRuntimePath.basename() + ".aria2")
        var aria2DownloadIsIncomplete = false
        if case .aria2 = downloader, aria2DownloadMetadataPath.exists {
            aria2DownloadIsIncomplete = true
        }
        if Current.files.fileExistsAtPath(expectedRuntimePath.string), aria2DownloadIsIncomplete == false {
            Logger.appState.info("Found existing runtime that will be used for installation at \(expectedRuntimePath).")
            return expectedRuntimePath.url
        }
        
        Logger.appState.info("Downloading \(runtime.visibleIdentifier) with \(downloader)")
        switch downloader {
        case .aria2:
            guard let aria2Path = Current.shell.aria2Path() else {
                throw Aria2UnavailableError()
            }

                for try await progress in downloadRuntimeWithAria2(runtime, to: expectedRuntimePath, aria2Path: aria2Path) {
                    Task { @MainActor in
                        self.setInstallationStep(of: runtime, to: .downloading(progress: progress), postNotification: false)
                    }
                }
                Logger.appState.debug("Done downloading runtime")

        case .urlSession:
            throw MessageError("Downloading runtimes with URLSession is not supported. Please use aria2")
        }
        return expectedRuntimePath.url
    }

    public func downloadRuntimeWithAria2(_ runtime: DownloadableRuntime, to destination: Path, aria2Path: Path) -> AsyncThrowingStream<Progress, Error> {
        guard let url = runtime.url else {
            return AsyncThrowingStream<Progress, Error> { continuation in
                continuation.finish(throwing: MessageError("Invalid or non existant runtime url"))
            }
        }
        
        let cookies = AppleAPI.Current.network.session.configuration.httpCookieStorage?.cookies(for: url) ?? []
    
        return Current.shell.downloadWithAria2Async(aria2Path, url, destination, cookies)
    }
    
    
    public func installFromImage(dmgURL: URL) async throws {
        try await self.runtimeService.installRuntimeImage(dmgURL: dmgURL)
    }
    
    func cancelRuntimeInstall(runtime: DownloadableRuntime) {
        // Cancel the publisher
        
        runtimePublishers[runtime.identifier]?.cancel()
        runtimePublishers[runtime.identifier] = nil
        
        // If the download is cancelled by the user, clean up the download files that aria2 creates.
        guard let source = runtime.source else {
            return
        }
        let url = URL(string: source)!
        let expectedRuntimePath = Path.xcodesApplicationSupport/"\(url.lastPathComponent)"
        let aria2DownloadMetadataPath = expectedRuntimePath.parent/(expectedRuntimePath.basename() + ".aria2")
   
        try? Current.files.removeItem(at: expectedRuntimePath.url)
        try? Current.files.removeItem(at: aria2DownloadMetadataPath.url)
        
        guard let index = self.downloadableRuntimes.firstIndex(where: { $0.identifier == runtime.identifier }) else { return }
        self.downloadableRuntimes[index].installState = .notInstalled
        
        updateInstalledRuntimes()
    }
    
    func runtimeInstallPath(xcode: Xcode, runtime: DownloadableRuntime) -> Path? {
        if let coreSimulatorInfo = coreSimulatorInfo(runtime: runtime) {
            let urlString = coreSimulatorInfo.path["relative"]!
            // app was not allowed to open up file:// url's so remove
            let fileRemovedString = urlString.replacingOccurrences(of: "file://", with: "")
            let url = URL(fileURLWithPath: fileRemovedString)
            
            return Path(url: url)!
        }
        return nil
    }
    
    func coreSimulatorInfo(runtime: DownloadableRuntime) -> CoreSimulatorImage? {
        return installedRuntimes.filter({
            $0.runtimeInfo.build == runtime.simulatorVersion.buildUpdate &&
            ((runtime.architectures ?? []).isEmpty ? true :
            $0.runtimeInfo.supportedArchitectures == runtime.architectures )}).first
    }
    
    func deleteRuntime(runtime: DownloadableRuntime) async throws {
        if let info = coreSimulatorInfo(runtime: runtime) {
            try await runtimeService.deleteRuntime(identifier: info.uuid)
            
            // give it some time to actually finish deleting before updating
            let updateInstalledRuntimes = DispatchWorkItem { [weak self] in
                self?.updateInstalledRuntimes()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: updateInstalledRuntimes)
        } else {
            throw MessageError("No simulator found with \(runtime.identifier)")
        }
    }
}
