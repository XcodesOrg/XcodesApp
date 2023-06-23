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
        self.runtimePublishers[runtime.identifier] = downloadRunTimeFull(runtime: runtime)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [unowned self] completion in
                    self.runtimePublishers[runtime.identifier] = nil
                    if case let .failure(error) = completion {
//                        // Prevent setting the app state error if it is an invalid session, we will present the sign in view instead
//                        if error as? AuthenticationError != .invalidSession {
//                            self.error = error
//                            self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.legibleLocalizedDescription)
//                        }
//                        if let index = self.allXcodes.firstIndex(where: { $0.id == id }) {
//                            self.allXcodes[index].installState = .notInstalled
//                        }
                    }
                },
                receiveValue: { _ in }
            )
    }
    
    func downloadRunTimeFull(runtime: DownloadableRuntime) -> AnyPublisher<(DownloadableRuntime, URL), Error> {
        // gets a proper cookie for runtimes
        
        return validateADCSession(path: runtime.downloadPath)
            .flatMap { _ in
                // we shouldn't have to be authenticated to download runtimes
                let downloader = Downloader(rawValue: UserDefaults.standard.string(forKey: "downloader") ?? "aria2") ?? .aria2
                Logger.appState.info("Downloading \(runtime.visibleIdentifier) with \(downloader)")
                
                return self.downloadRuntime(for: runtime, downloader: downloader, progressChanged: { [unowned self] progress in
                    DispatchQueue.main.async {
                        self.setInstallationStep(of: runtime, to: .downloading(progress: progress))
                    }
                })
                .map { return (runtime, $0) }
            }
            .eraseToAnyPublisher()
    }
    
    func downloadRuntime(for runtime: DownloadableRuntime, downloader: Downloader, progressChanged: @escaping (Progress) -> Void) -> AnyPublisher<URL, Error> {
        // Check to see if the dmg is in the expected path in case it was downloaded but failed to install
    
        // call https://developerservices2.apple.com/services/download?path=/Developer_Tools/watchOS_10_beta/watchOS_10_beta_Simulator_Runtime.dmg 1st to get cookie
        // use runtime.url for final with cookies
        
        // Check to see if the archive is in the expected path in case it was downloaded but failed to install
        let expectedRuntimePath = Path.xcodesApplicationSupport/"\(runtime.name).\(runtime.name.suffix(fromLast: "."))"
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
//            let destination = Path.xcodesApplicationSupport/"Xcode-\(availableXcode.version).\(availableXcode.filename.suffix(fromLast: "."))"
            switch downloader {
            case .aria2:
                let aria2Path = Path(url: Bundle.main.url(forAuxiliaryExecutable: "aria2c")!)!
                return downloadRuntimeWithAria2(
                    runtime,
                    to: expectedRuntimePath,
                    aria2Path: aria2Path,
                    progressChanged: progressChanged)
//                return downloadXcodeWithAria2(
//                    availableXcode,
//                    to: destination,
//                    aria2Path: aria2Path,
//                    progressChanged: progressChanged
//                )
            case .urlSession:
                
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
}
