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
                    let simulatorBuildUpdate = downloadableRuntimes.sdkToSimulatorMappings.filter { SDKToSimulatorMapping in
                        SDKToSimulatorMapping.simulatorBuildUpdate == runtime.simulatorVersion.buildUpdate
                    }
                    updatedRuntime.sdkBuildUpdate = simulatorBuildUpdate.map { $0.sdkBuildUpdate }
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
                Logger.appState.info("Loading Installed runtimes")
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
        runtimePublishers[runtime.identifier] = Task {
            do {
                let downloadedURL = try await downloadRunTimeFull(runtime: runtime)
                if !Task.isCancelled {
                    Logger.appState.debug("Installing runtime: \(runtime.name)")
                    DispatchQueue.main.async {
                        self.setInstallationStep(of: runtime, to: .installing)
                    }
                    switch runtime.contentType {
                    case .package:
                        // not supported yet (do we need to for old packages?)
                        throw "Installing via package not support - please install manually from \(downloadedURL.description)"
                    case .diskImage:
                        try await self.installFromImage(dmgURL: downloadedURL)
                        DispatchQueue.main.async {
                            self.setInstallationStep(of: runtime, to: .trashingArchive)
                        }
                        try Current.files.removeItem(at: downloadedURL)
                    }
                
                    DispatchQueue.main.async {
                        guard let index = self.downloadableRuntimes.firstIndex(where: { $0.identifier == runtime.identifier }) else { return }
                        self.downloadableRuntimes[index].installState = .installed
                    }
                    updateInstalledRuntimes()
                }
              
            }
            catch {
                Logger.appState.error("Error downloading runtime: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.error = error
                    self.presentedAlert = .generic(title: localizeString("Alert.Install.Error.Title"), message: error.legibleLocalizedDescription)
                }
            }
        }
    }
    
    func downloadRunTimeFull(runtime: DownloadableRuntime) async throws -> URL {
        // sets a proper cookie for runtimes
        try await validateADCSession(path: runtime.downloadPath)
        
        let downloader = Downloader(rawValue: UserDefaults.standard.string(forKey: "downloader") ?? "aria2") ?? .aria2
        
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
            return expectedRuntimePath.url
        }
        
        Logger.appState.info("Downloading \(runtime.visibleIdentifier) with \(downloader)")
        switch downloader {
        case .aria2:
            let aria2Path = Path(url: Bundle.main.url(forAuxiliaryExecutable: "aria2c")!)!
                for try await progress in downloadRuntimeWithAria2(runtime, to: expectedRuntimePath, aria2Path: aria2Path) {
                    DispatchQueue.main.async {
                        self.setInstallationStep(of: runtime, to: .downloading(progress: progress), postNotification: false)
                    }
                }
                Logger.appState.debug("Done downloading runtime")

        case .urlSession:
            throw "Downloading runtimes with URLSession is not supported. Please use aria2"
        }
        return expectedRuntimePath.url
    }

    public func downloadRuntimeWithAria2(_ runtime: DownloadableRuntime, to destination: Path, aria2Path: Path) -> AsyncThrowingStream<Progress, Error> {
        let cookies = AppleAPI.Current.network.session.configuration.httpCookieStorage?.cookies(for: runtime.url) ?? []
    
        return Current.shell.downloadWithAria2Async(aria2Path, runtime.url, destination, cookies)
    }
    
    
    public func installFromImage(dmgURL: URL) async throws {
        try await self.runtimeService.installRuntimeImage(dmgURL: dmgURL)
    }
    
    func cancelRuntimeInstall(runtime: DownloadableRuntime) {
        // Cancel the publisher
        
        runtimePublishers[runtime.identifier]?.cancel()
        runtimePublishers[runtime.identifier] = nil
        
        // If the download is cancelled by the user, clean up the download files that aria2 creates.
        let url = URL(string: runtime.source)!
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
        return installedRuntimes.filter({ $0.runtimeInfo.build == runtime.simulatorVersion.buildUpdate }).first
    }
    
    func deleteRuntime(runtime: DownloadableRuntime) async throws {
        if let info = coreSimulatorInfo(runtime: runtime) {
            try await runtimeService.deleteRuntime(identifier: info.uuid)
            
            // give it some time to actually finish deleting before updating
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateInstalledRuntimes()
            }
        } else {
            throw "No simulator found with \(runtime.identifier)"
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
extension AnyPublisher where Failure: Error {
    struct Subscriber {
        fileprivate let send: (Output) -> Void
        fileprivate let complete: (Subscribers.Completion<Failure>) -> Void

        func send(_ value: Output) { self.send(value) }
        func send(completion: Subscribers.Completion<Failure>) { self.complete(completion) }
    }

    init(_ closure: (Subscriber) -> AnyCancellable) {
        let subject = PassthroughSubject<Output, Failure>()

        let subscriber = Subscriber(
            send: subject.send,
            complete: subject.send(completion:)
        )
        let cancel = closure(subscriber)

        self = subject
            .handleEvents(receiveCancel: cancel.cancel)
            .eraseToAnyPublisher()
    }
}

extension AnyPublisher where Failure == Error {
    init(taskPriority: TaskPriority? = nil, asyncFunc: @escaping () async throws -> Output) {
        self.init { subscriber in
            let task = Task(priority: taskPriority) {
                do {
                    subscriber.send(try await asyncFunc())
                    subscriber.send(completion: .finished)
                } catch {
                    subscriber.send(completion: .failure(error))
                }
            }
            return AnyCancellable { task.cancel() }
        }
    }
}
