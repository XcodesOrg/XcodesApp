import AppKit
import Combine
import SwiftUI
import XcodesCleanupKit

struct CleanupFoldersView: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    // Folder editing does not observe scan results, progress, or selection changes.
    let model: CleanupModel
    let isSettings: Bool
    @State private var folders: [CleanupFolder]
    @State private var error: String?
    @State private var isCleaning: Bool
    @State private var scanDepth: Int

    init(model: CleanupModel, isSettings: Bool = false) {
        self.model = model
        self.isSettings = isSettings
        _folders = State(initialValue: model.scanFolders)
        _isCleaning = State(initialValue: model.isCleaning)
        _scanDepth = State(initialValue: model.scanDepth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Scan Folders").font(.title2.bold())
                Spacer()
                Menu("Add Folder") {
                    ForEach(CleanupFolder.Preset.allCases) { preset in
                        Button(preset.title) {
                            do { add([try preset.folder()]) }
                            catch { self.error = error.localizedDescription }
                        }
                            .disabled(folders.contains { $0.preset == preset })
                    }
                    let removed = model.suggestedDeveloperFolders.filter { candidate in !folders.contains { $0.id == candidate.id } }
                    if !removed.isEmpty {
                        Menu("Developer Folders") {
                            ForEach(removed) { folder in Button(folder.name) { add([folder]) } }
                        }
                    }
                    Divider()
                    Button("Choose Folder…", action: chooseFolder)
                }
                .disabled(isCleaning)
            }
            HStack {
                Picker("Scan depth", selection: $scanDepth) {
                    ForEach([1, 2, 3, 5, 10], id: \.self) { depth in
                        Text("\(depth) \(depth == 1 ? "level" : "levels")").tag(depth)
                    }
                    if scanDepth > 0 && ![1, 2, 3, 5, 10].contains(scanDepth) {
                        Text("\(scanDepth) levels").tag(scanDepth)
                    }
                    Text("Unlimited").tag(0)
                }
                .fixedSize().disabled(isCleaning)
                Text("Added folders only. Limited scans show partial sizes. Deeper scans take longer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .help("The selected folder is level 0. One level lists immediate files and folders. Developer folders are always scanned fully.")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(folders) { folder in
                        HStack(spacing: 8) {
                            Text(folder.url.path).font(.caption).lineLimit(1).truncationMode(.middle)
                                .help(folder.url.path)
                            Button { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) } label: {
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .buttonStyle(.plain).help("Reveal in Finder").accessibilityLabel("Reveal \(folder.name) in Finder")
                            Spacer(minLength: 8)
                            Button("Remove") {
                                folders.removeAll { $0.id == folder.id }
                                error = nil
                                saveIfSettings()
                            }
                            .disabled(isCleaning)
                            .help("Remove from the scan")
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    if folders.isEmpty { Text("Add a suggested folder or choose your own.").foregroundStyle(.secondary).padding(.vertical, 24) }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if !isSettings {
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Done") {
                        do {
                            try model.replaceScanFolders(folders, rescan: false)
                            guard model.setScanDepth(scanDepth) else {
                                throw NSError(domain: "CleanupConfiguration", code: 1, userInfo: [NSLocalizedDescriptionKey: model.message ?? "Could not save scan depth."])
                            }
                            dismiss()
                        }
                        catch { self.error = error.localizedDescription }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCleaning)
                }
            }
        }
        .padding(isSettings ? 0 : 20)
        .frame(width: isSettings ? nil : 680, height: isSettings ? 360 : 440)
        .onReceive(model.$folders.combineLatest(model.$excludedFolders)) { custom, excluded in
            if isSettings {
                let updated = model.suggestedDeveloperFolders.filter { !excluded.contains($0.categoryID) } + custom
                if folders != updated { folders = updated }
            }
        }
        .onReceive(model.$isCleaning.removeDuplicates()) { isCleaning = $0 }
        .onReceive(model.$scanDepth.removeDuplicates()) { if isSettings { scanDepth = $0 } }
        .onChange(of: scanDepth) {
            if isSettings && !model.setScanDepth(scanDepth) {
                error = model.message; scanDepth = model.scanDepth
            }
        }
    }

    private func saveIfSettings() {
        guard isSettings else { return }
        do { try model.replaceScanFolders(folders) }
        catch { self.error = error.localizedDescription; folders = model.scanFolders }
    }

    private func add(_ added: [CleanupFolder]) {
        error = nil
        for folder in added {
            guard !folders.contains(where: { $0.canonicalPath == folder.canonicalPath }) else {
                error = "That folder is already in the scan list."; continue
            }
            folders.append(folder)
        }
        saveIfSettings()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        add(panel.urls.map { CleanupFolder(id: UUID(), name: $0.lastPathComponent, url: $0, preset: nil) })
    }
}
