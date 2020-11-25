import AppKit
import AppleAPI
import Combine
import Path
import PromiseKit
import XcodesKit

class AppState: ObservableObject {
    private let list = XcodeList()
    private lazy var installer = XcodeInstaller(configuration: Configuration(), xcodeList: list)
    
    struct XcodeVersion: Identifiable {
        let title: String
        let installState: InstallState
        let selected: Bool
        let path: String?
        var id: String { title }
        var installed: Bool { installState == .installed }
    }
    enum InstallState: Equatable {
        case notInstalled
        case installing(Progress)
        case installed
    }
    @Published var allVersions: [XcodeVersion] = []
    
    struct AlertContent: Identifiable {
        var title: String
        var message: String
        var id: String { title + message }
    }
    @Published var error: AlertContent?
    
    @Published var presentingSignInAlert = false

    func load() {
//        if list.shouldUpdate {
            update()
                .done { _ in
                    self.updateAllVersions()
                }
                .catch { error in
                    self.error = AlertContent(title: "Error", 
                                              message: error.localizedDescription)
                }
//        }
//        else {
//            updateAllVersions()
//        }        
    }
    
    func validateSession() -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            return Current.network.validateSession()
        }
        .recover { _ in
            self.presentingSignInAlert = true
        }
    }
    
    func continueLogin(username: String, password: String) -> Promise<Void> {
        firstly { () -> Promise<Void> in
            self.installer.login(username, password: password)
        }
        .recover { error -> Promise<Void> in
            XcodesKit.Current.logging.log(error.legibleLocalizedDescription)

            if case Client.Error.invalidUsernameOrPassword = error {
                self.presentingSignInAlert = true
            }
            return Promise(error: error)
        }
    }
    
    public func update() -> Promise<[Xcode]> {
        return firstly { () -> Promise<Void> in
            validateSession()
        }
        .then { () -> Promise<[Xcode]> in
            self.list.update()
        }
    }
    
    private func updateAllVersions() {
        let installedXcodes = Current.files.installedXcodes(Path.root/"Applications")
        var allXcodeVersions = list.availableXcodes.map { $0.version }
        for installedXcode in installedXcodes {
            // If an installed version isn't listed online, add the installed version
            if !allXcodeVersions.contains(where: { version in
                version.isEquivalentForDeterminingIfInstalled(toInstalled: installedXcode.version)
            }) {
                allXcodeVersions.append(installedXcode.version)
            }
            // If an installed version is the same as one that's listed online which doesn't have build metadata, replace it with the installed version with build metadata
            else if let index = allXcodeVersions.firstIndex(where: { version in
                version.isEquivalentForDeterminingIfInstalled(toInstalled: installedXcode.version) &&
                version.buildMetadataIdentifiers.isEmpty
            }) {
                allXcodeVersions[index] = installedXcode.version
            }
        }

        allVersions = allXcodeVersions
            .sorted(by: >)
            .map { xcodeVersion in
                let installedXcode = installedXcodes.first(where: { xcodeVersion.isEquivalentForDeterminingIfInstalled(toInstalled: $0.version) })
                return XcodeVersion(
                    title: xcodeVersion.xcodeDescription, 
                    installState: installedXcodes.contains(where: { xcodeVersion.isEquivalentForDeterminingIfInstalled(toInstalled: $0.version) }) ? .installed : .notInstalled,
                    selected: installedXcode?.path.string.contains("11.4.1") == true, 
                    path: installedXcode?.path.string
                )
            }
    }
    
    func install(id: String) {
        // TODO:
    }
    
    func uninstall(id: String) {
        guard let installedXcode = Current.files.installedXcodes(Path.root/"Applications").first(where: { $0.version.xcodeDescription == id }) else { return }
        // TODO: would be nice to have a version of this method that just took the InstalledXcode
        installer.uninstallXcode(installedXcode.version.xcodeDescription, destination: Path.root/"Applications")
            .done {
                
            }
            .catch { error in
            
            }
    }
    
    func reveal(id: String) {
        // TODO: show error if not
        guard let installedXcode = Current.files.installedXcodes(Path.root/"Applications").first(where: { $0.version.xcodeDescription == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([installedXcode.path.url])
    }

    func select(id: String) {
        // TODO:
    }
}
