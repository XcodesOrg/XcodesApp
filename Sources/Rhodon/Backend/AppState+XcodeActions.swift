import AppKit
import Foundation
import os.log
import Path
import RhodonKit

extension AppState {
    func uninstall(xcode: Xcode) {
        guard
            let installedXcodePath = xcode.installedPath,
            uninstallTask == nil
        else { return }

        uninstallTask = Task {
            do {
                try current.files.trashItem(at: installedXcodePath.url)
                await updateSelectedXcodePath()
            } catch {
                self.error = error
                presentedAlert = .generic(
                    title: "Unable to uninstall Xcode",
                    message: error.legibleLocalizedDescription
                )
            }
            uninstallTask = nil
        }
    }

    func reveal(_ path: Path?) {
        // Follow-up: show error if not
        guard let path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([path.url])
    }

    func reveal(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func select(xcode: Xcode, shouldPrepareUserForHelperInstallation: Bool = true) {
        guard helperInstallState == .installed || shouldPrepareUserForHelperInstallation == false else {
            isPreparingUserForActionRequiringHelper = { [unowned self] userConsented in
                guard userConsented else { return }
                select(xcode: xcode, shouldPrepareUserForHelperInstallation: false)
            }
            presentedAlert = .privilegedHelper
            return
        }

        guard
            var installedXcodePath = xcode.installedPath,
            selectTask == nil
        else { return }

        if onSelectActionType == .rename {
            guard let newDestinationXcodePath = renameToXcode(xcode: xcode) else { return }
            installedXcodePath = newDestinationXcodePath
        }

        selectTask = Task {
            do {
                try await installHelperIfNecessary()
                try await current.helper.switchXcodePath(installedXcodePath.string)
                await updateSelectedXcodePath()
                if createSymLinkOnSelect {
                    createSymbolicLink(xcode: xcode)
                }
            } catch {
                self.error = error
                presentedAlert = .generic(
                    title: "Unable to select Xcode",
                    message: error.legibleLocalizedDescription
                )
            }
            selectTask = nil
        }
    }

    func open(xcode: Xcode, openInRosetta: Bool? = false) {
        switch xcode.installState {
        case let .installed(path):
            let config = NSWorkspace.OpenConfiguration()
            if openInRosetta ?? false {
                config.architecture = CPU_TYPE_X86_64
            }
            config.allowsRunningApplicationSubstitution = false
            NSWorkspace.shared.openApplication(at: path.url, configuration: config)
        default:
            Logger.appState.error("\(xcode.id.version) is not installed")
            return
        }
    }

    func copyPath(xcode: Xcode) {
        guard let installedXcodePath = xcode.installedPath else { return }

        NSPasteboard.general.declareTypes([.URL, .string], owner: nil)
        NSPasteboard.general.writeObjects([installedXcodePath.url as NSURL])
        NSPasteboard.general.setString(installedXcodePath.string, forType: .string)
    }

    func copyReleaseNote(from url: URL?) {
        guard let url else { return }
        NSPasteboard.general.declareTypes([.URL, .string], owner: nil)
        NSPasteboard.general.writeObjects([url as NSURL])
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func createSymbolicLink(xcode: Xcode, isBeta: Bool = false) {
        guard let installedXcodePath = xcode.installedPath else { return }

        let destinationPath = Path.installDirectory / "Xcode\(isBeta ? "-Beta" : "").app"

        if FileManager.default.fileExists(atPath: destinationPath.string) {
            do {
                let attributes: [FileAttributeKey: Any]? = try? FileManager.default
                    .attributesOfItem(atPath: destinationPath.string)

                if attributes?[.type] as? FileAttributeType == FileAttributeType.typeSymbolicLink {
                    try FileManager.default.removeItem(atPath: destinationPath.string)
                    Logger.appState.info("Successfully deleted old symlink")
                } else {
                    presentedAlert = .generic(
                        title: "Unable to create symbolic Link",
                        message: "Xcode.app exists and is not a symbolic link"
                    )
                    return
                }
            } catch {
                presentedAlert = .generic(title: "Unable to create symbolic Link", message: error.localizedDescription)
            }
        }

        do {
            try FileManager.default.createSymbolicLink(
                atPath: destinationPath.string,
                withDestinationPath: installedXcodePath.string
            )
            Logger.appState.info("Successfully created symbolic link with Xcode\(isBeta ? "-Beta" : "").app")
        } catch {
            Logger.appState.error("Unable to create symbolic Link")
            self.error = error
            presentedAlert = .generic(
                title: "Unable to create symbolic Link",
                message: error.legibleLocalizedDescription
            )
        }
    }

    func renameToXcode(xcode: Xcode) -> Path? {
        guard let installedXcodePath = xcode.installedPath else { return nil }

        let destinationPath = Path.installDirectory / "Xcode.app"

        if FileManager.default.fileExists(atPath: destinationPath.string) {
            if let originalXcode = current.files.installedXcode(destination: destinationPath) {
                let newName = "Xcode-\(originalXcode.version.descriptionWithoutBuildMetadata).app"
                Logger.appState.debug("Found Xcode.app - renaming back to \(newName)")
                do {
                    try destinationPath.rename(to: newName)
                } catch {
                    Logger.appState.error("Unable to create rename Xcode.app back to original")
                    self.error = error
                    presentedAlert = .generic(
                        title: "Unable to create symbolic Link",
                        message: error.legibleLocalizedDescription
                    )
                }
            }
        }

        Logger.appState.debug("Found Xcode.app - renaming back to Xcode.app")
        do {
            return try installedXcodePath.rename(to: "Xcode.app")
        } catch {
            Logger.appState.error("Unable to create rename Xcode.app back to original")
            self.error = error
            presentedAlert = .generic(
                title: "Unable to create symbolic Link",
                message: error.legibleLocalizedDescription
            )
        }
        return nil
    }

}
