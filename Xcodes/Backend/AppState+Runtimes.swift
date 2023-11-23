import Foundation
import XcodesKit
import OSLog
import Combine
import Path
import AppleAPI

extension AppState {
    func updateDownloadableRuntimes() {
        Task {
            do {
                
                let downloadableRuntimes = try await self.runtimeService.downloadableRuntimes()
                let runtimes = downloadableRuntimes.downloadables.map { runtime in
                    var updatedRuntime = runtime
                    
                    // This loops through and matches up the simulatorVersion to the mappings
                    let simulatorBuildUpdate = downloadableRuntimes.sdkToSimulatorMappings.first { SDKToSimulatorMapping in
                        SDKToSimulatorMapping.simulatorBuildUpdate == runtime.simulatorVersion.buildUpdate
                    }
                    updatedRuntime.sdkBuildUpdate = simulatorBuildUpdate?.sdkBuildUpdate
                    return updatedRuntime
                }
    
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
    
    func downloadRuntime(runtime: DownloadableRuntime) {
        Task {
            do {
                try await downloadRunTimeFull(runtime: runtime)
            }
            catch {
                Logger.appState.error("Error downloading runtime: \(error.localizedDescription)")
            }
        }
        
//        self.runtimePublishers[runtime.identifier] = downloadRunTimeFull(runtime: runtime)
//            .receive(on: DispatchQueue.main)
//            .sink(
//                receiveCompletion: { [unowned self] completion in
//                    self.runtimePublishers[runtime.identifier] = nil
//                    if case let .failure(error) = completion {
//                        Logger.appState.error("Error downloading runtime: \(error.localizedDescription)")
////                        // Prevent setting the app state error if it is an invalid session, we will present the sign in view instead
////                        if error as? AuthenticationError != .invalidSession {
////                            self.error = error
////                            self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.legibleLocalizedDescription)
////                        }
////                        if let index = self.allXcodes.firstIndex(where: { $0.id == id }) {
////                            self.allXcodes[index].installState = .notInstalled
////                        }
//                    }
//                },
//                receiveValue: { _ in }
//            )
    }
    
    func downloadRunTimeFull(runtime: DownloadableRuntime) async throws {
        // sets a proper cookie for runtimes
        try await validateADCSession(path: runtime.downloadPath)
        
        let downloader = Downloader(rawValue: UserDefaults.standard.string(forKey: "downloader") ?? "aria2") ?? .aria2
        Logger.appState.info("Downloading \(runtime.visibleIdentifier) with \(downloader)")
        
        let url = try await self.downloadRuntime(for: runtime, downloader: downloader, progressChanged: { [unowned self] progress in
            DispatchQueue.main.async {
                self.setInstallationStep(of: runtime, to: .downloading(progress: progress))
            }
        }).async()
        
        Logger.appState.debug("Done downloading: \(url)")
        //self.setInstallationStep(of: runtime, to: .downloading(progress: progress))
        switch runtime.contentType {
        case .package:
            try await self.installFromPackage(dmgURL: url, runtime: runtime)
        case .diskImage:
            try await self.installFromImage(dmgURL: url)
        }
    }
    
    func downloadRuntime(for runtime: DownloadableRuntime, downloader: Downloader, progressChanged: @escaping (Progress) -> Void) -> AnyPublisher<URL, Error> {
        // Check to see if the dmg is in the expected path in case it was downloaded but failed to install
    
        // call https://developerservices2.apple.com/services/download?path=/Developer_Tools/watchOS_10_beta/watchOS_10_beta_Simulator_Runtime.dmg 1st to get cookie
        // use runtime.url for final with cookies
        
        // Check to see if the archive is in the expected path in case it was downloaded but failed to install
//        let expectedRuntimePath = Path.xcodesApplicationSupport/"\(runtime.name).\(runtime.name.suffix(fromLast: "."))"
        let url = URL(string: runtime.source)!
        let expectedRuntimePath = Path.xcodesApplicationSupport/"\(url.lastPathComponent)"
        // aria2 downloads directly to the destination (instead of into /tmp first) so we need to make sure that the download isn't incomplete
        let aria2DownloadMetadataPath = expectedRuntimePath.parent/(expectedRuntimePath.basename() + ".aria2")
        var aria2DownloadIsIncomplete = false
        if case .aria2 = downloader, aria2DownloadMetadataPath.exists {
            aria2DownloadIsIncomplete = true
        }
        if Current.files.fileExistsAtPath(expectedRuntimePath.string), aria2DownloadIsIncomplete == false {
            Logger.appState.info("Found existing runtime that will be used for installation at \(expectedRuntimePath).")
            return Just(expectedRuntimePath.url)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        else {

            Logger.appState.info("Downloading runtime: \(url.lastPathComponent)")
            switch downloader {
            case .aria2:
                let aria2Path = Path(url: Bundle.main.url(forAuxiliaryExecutable: "aria2c")!)!
                return downloadRuntimeWithAria2(
                    runtime,
                    to: expectedRuntimePath,
                    aria2Path: aria2Path,
                    progressChanged: progressChanged)

            case .urlSession:
                // TODO: Support runtime download via URL Session
                return Just(runtime.url)
                                .setFailureType(to: Error.self)
                                .eraseToAnyPublisher()
                
//                return downloadXcodeWithURLSession(
//                    availableXcode,
//                    to: destination,
//                    progressChanged: progressChanged
//                )
            }
        }
    }
    
    public func downloadRuntimeWithAria2(_ runtime: DownloadableRuntime, to destination: Path, aria2Path: Path, progressChanged: @escaping (Progress) -> Void) -> AnyPublisher<URL, Error> {
        let cookies = AppleAPI.Current.network.session.configuration.httpCookieStorage?.cookies(for: runtime.url) ?? []
    
        let (progress, publisher) = Current.shell.downloadWithAria2(
            aria2Path,
            runtime.url,
            destination,
            cookies
        )
        progressChanged(progress)
        return publisher
            .map { _ in destination.url }
            .eraseToAnyPublisher()
    }
    
    
    public func installFromImage(dmgURL: URL) async throws {
        
        try? self.runtimeService.installRuntimeImage(dmgURL: dmgURL)
        
    }
    
    public func installFromPackage(dmgURL: URL, runtime: DownloadableRuntime) async throws {
        Logger.appState.info("Mounting DMG")
       
        do {
            let mountedUrl = try await self.runtimeService.mountDMG(dmgUrl: dmgURL)
            
            // 2-Get the first path under the mounted path, should be a .pkg
            let pkgPath = Path(url: mountedUrl)!.ls().first!
            try Path.xcodesCaches.mkdir().setCurrentUserAsOwner()
            
            let expandedPkgPath = Path.xcodesCaches/runtime.identifier
            //try expandedPkgPath.mkdir()
            Logger.appState.info("PKG Path: \(pkgPath)")
            Logger.appState.info("Expanded PKG Path: \(expandedPkgPath)")
            //try? Current.files.removeItem(at: expandedPkgPath.url)
            
            // 5-Expand (not install) the pkg to temporary path
            try await self.runtimeService.expand(pkgPath: pkgPath, expandedPkgPath: expandedPkgPath)
            //try await self.runtimeService.unmountDMG(mountedURL: mountedUrl)
            
        } catch {
            Logger.appState.error("Error installing runtime: \(error.localizedDescription)")
        }
    }
}

extension AnyPublisher {
    func async() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            
            cancellable = first()
                .sink { result in
                    switch result {
                    case .finished:
                        break
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                } receiveValue: { value in
                    continuation.resume(with: .success(value))
                }
        }
    }
}
