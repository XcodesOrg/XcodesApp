import Foundation
import os
import XCTest
import XcodesCleanupKit
@testable import Xcodes

final class CleanupOperationsTests: XCTestCase {
    func testSimulatorInventoryRetainsAvailabilityAndAllDeviceNames() throws {
        let unavailable = UUID().uuidString
        let available = UUID().uuidString
        let booted = UUID().uuidString
        let unknown = UUID().uuidString
        let data = Data("""
        {"devices":{"runtime":[
            {"udid":"\(unavailable)","name":"Old iPhone","state":"Shutdown","isAvailable":false},
            {"udid":"\(available)","name":"Current iPhone","state":"Shutdown","isAvailable":true},
            {"udid":"\(booted)","name":"Running iPhone","state":"Booted","isAvailable":false},
            {"udid":"\(unknown)","name":"Unknown iPhone","state":"Shutdown"},
            {"udid":"not-a-uuid","name":"Invalid","state":"Shutdown","isAvailable":false}
        ]}}
        """.utf8)
        let inventory = try CleanupOperations.decodeSimulatorDevices(data)
        XCTAssertEqual(inventory.devices[unavailable]?.isAvailable, false)
        XCTAssertEqual(inventory.devices[booted]?.state, "Booted")
        XCTAssertEqual(inventory.devices.mapValues(\.name), [
            unavailable: "Old iPhone", available: "Current iPhone", booted: "Running iPhone", unknown: "Unknown iPhone"
        ])
    }

    func testChangedIdentityNeverReachesTrashOperation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("file")
        try Data("original".utf8).write(to: path)
        let session = try ScanSession(request: ScanRequest(roots: [FilesystemPath(folder)]))
        let result = try await session.result()
        let item = try XCTUnwrap(result.item(at: FilesystemPath(path)))
        // Preserve the original inode elsewhere to prevent immediate inode reuse.
        try FileManager.default.moveItem(at: path, to: folder.appendingPathComponent("original"))
        try Data("replacement".utf8).write(to: path)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        var files = Files()
        files.trashItem = { url in calls.withLock { $0 += 1 }; return url }
        do { try await CleanupOperations.trash(item, files: files); XCTFail("Changed identity must be rejected") }
        catch { XCTAssertTrue(error is CleanupOperationError) }
        XCTAssertEqual(calls.withLock { $0 }, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }

    func testTrashUsesInjectedOperationForValidatedItem() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("file")
        try Data("original".utf8).write(to: path)
        let session = try ScanSession(request: ScanRequest(roots: [FilesystemPath(folder)]))
        let result = try await session.result()
        let item = try XCTUnwrap(result.item(at: FilesystemPath(path)))
        let calls = OSAllocatedUnfairLock(initialState: [URL]())
        var files = Files()
        files.trashItem = { url in calls.withLock { $0.append(url) }; return url }
        try await CleanupOperations.trash(item, files: files)
        XCTAssertEqual(calls.withLock { $0 }, [path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }

    @MainActor
    func testCategorySelectionTogglesEligibleItemsAndPreservesIndividualChoices() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["one", "two"] { try Data(name.utf8).write(to: folder.appendingPathComponent(name)) }
        let missing = try FilesystemPath(folder.appendingPathComponent("missing"))
        let session = try ScanSession(request: ScanRequest(roots: [FilesystemPath(folder), missing]))
        let result = try await session.result()
        let model = CleanupModel()
        model.finishScan(result)
        let root = try XCTUnwrap(result.item(at: FilesystemPath(folder)))
        let children = result.children(of: root.id)
        let unavailable = try XCTUnwrap(result.item(at: missing))
        let items = children + [unavailable]
        // Activity has not been checked yet; preparing a selection is still allowed.
        XCTAssertEqual(model.selectableItems(items).count, 2)
        model.toggleSelection(items)
        XCTAssertEqual(model.selected, Set(children.map(\.id)))
        model.setSelected(children[0], selected: false)
        XCTAssertEqual(model.selected.count, 1)
        model.toggleSelection(items)
        XCTAssertEqual(model.selected.count, 2)
        XCTAssertNotNil(model.blockingReason(children[0], classification: .review))
        model.toggleSelection(items)
        XCTAssertTrue(model.selected.isEmpty)
    }

    @MainActor
    func testReopeningRetainsCompletedResultsAndSelection() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("file".utf8).write(to: folder.appendingPathComponent("file"))
        let session = try ScanSession(request: ScanRequest(roots: [FilesystemPath(folder)]))
        let result = try await session.result()
        let item = try XCTUnwrap(result.children(of: result.rootIDs[0]).first)
        let model = CleanupModel()
        model.finishScan(result)
        model.setSelected(item, selected: true)
        model.close()
        model.open(appState: AppState())
        XCTAssertEqual(model.result?.scanID, result.scanID)
        XCTAssertEqual(model.selected, [item.id])
        XCTAssertFalse(model.isScanning)
        model.close()
    }


    @MainActor
    func testProgressUpdatesExposeCompletedTopLevelFoldersAndSizes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("completed"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(repeating: 7, count: 40_000).write(to: folder.appendingPathComponent("completed/file"))
        let category = FindingCategory(id: "fixture", title: "Fixture", explanation: "Fixture", location: try FilesystemPath(folder), classification: .review)
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category]))
        let progressResult = try await session.result()
        let model = CleanupModel()
        // Feed a queryable progress view without invoking the app's finishScan path.
        model.configureScan(categories: [category], policyCategories: [category])
        model.receiveScanProgress(progressResult)
        let items = model.items(for: category)
        XCTAssertEqual(items.map(\.displayName), ["completed"])
        XCTAssertEqual(items[0].status, .complete)
        XCTAssertGreaterThan(items[0].allocatedBytes, 0)
        XCTAssertEqual(model.sections.first?.allocatedBytes, progressResult.roots[0].allocatedBytes)
    }

    @MainActor
    func testTrashLabelDoesNotDescribePermanentDeviceDeletionAsTrash() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let devices = folder.appendingPathComponent("devices")
        let device = devices.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("device".utf8).write(to: device.appendingPathComponent("data"))
        let ordinary = folder.appendingPathComponent("ordinary")
        try Data("ordinary".utf8).write(to: ordinary)
        let category = FindingCategory(id: "simulators", title: "Devices", explanation: "Device data", location: try FilesystemPath(devices), classification: .simulatorDevice)
        let session = try ScanSession(request: ScanRequest(roots: [FilesystemPath(folder)], categories: [category]))
        let result = try await session.result()
        let deviceItem = try XCTUnwrap(result.item(at: FilesystemPath(device)))
        let ordinaryItem = try XCTUnwrap(result.item(at: FilesystemPath(ordinary)))
        let model = CleanupModel()
        model.finishScan(result)
        model.selected = [ordinaryItem.id]
        XCTAssertEqual(model.cleanupActionTitle, "Move to Trash")
        XCTAssertFalse(model.cleanupIncludesDevices)
        model.selected = [deviceItem.id]
        XCTAssertEqual(model.cleanupActionTitle, "Delete Devices")
        XCTAssertTrue(model.cleanupIncludesDevices)
        model.selected = [deviceItem.id, ordinaryItem.id]
        XCTAssertEqual(model.cleanupActionTitle, "Move to Trash & Delete Devices")
    }


    @MainActor
    func testLargeFindingSelectionPreparation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for index in 0..<300 {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("project-\(index)/node_modules"), withIntermediateDirectories: true)
        }
        let session = try ScanSession(request: ScanRequest(roots: [FilesystemPath(folder)], detectNodeModules: true))
        let result = try await session.result()
        let finding = try XCTUnwrap(result.findings.first { $0.categoryID == "nodeModules" })
        let model = CleanupModel()
        model.finishScan(result)
        let items = model.items(for: finding)
        let start = ContinuousClock.now
        for _ in 0..<3 { XCTAssertEqual(model.selectableItems(items).count, 300) }
        let duration = start.duration(to: .now)
        print("Cleanup selection preparation (300 folders, three passes): \(duration)")
    }


    @MainActor
    func testCompletedSectionsSortBySizeAndTotalDoesNotDoubleCountOverlap() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("small"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("large"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(repeating: 1, count: 1_000).write(to: folder.appendingPathComponent("small/file"))
        try Data(repeating: 2, count: 100_000).write(to: folder.appendingPathComponent("large/file"))
        let categories = try ["small", "large", "all"].map { name in
            FindingCategory(id: name, title: name, explanation: "Fixture", location: try FilesystemPath(name == "all" ? folder : folder.appendingPathComponent(name)), classification: .review)
        }
        let session = try ScanSession(request: ScanRequest(roots: [FilesystemPath(folder), categories[1].location], categories: categories))
        let result = try await session.result()
        let model = CleanupModel()
        model.configureScan(categories: categories, policyCategories: categories)
        model.finishScan(result)
        XCTAssertEqual(model.sections.count, 3)
        let sizes = model.sections.map(\.allocatedBytes)
        XCTAssertEqual(sizes, sizes.sorted(by: >))
        XCTAssertEqual(model.sections.first?.id, "category:all")
        XCTAssertEqual(model.totalScannedBytes, result.roots[0].allocatedBytes)
        XCTAssertLessThan(model.totalScannedBytes, sizes.reduce(0, +))
    }

    @MainActor
    func testClassificationCacheRefreshesWhenManagementPolicyChanges() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("file".utf8).write(to: folder.appendingPathComponent("file"))
        let category = FindingCategory(id: "cache", title: "Cache", explanation: "Fixture", location: try FilesystemPath(folder), classification: .regenerable)
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category]))
        let result = try await session.result()
        let item = try XCTUnwrap(result.children(of: result.rootIDs[0]).first)
        let model = CleanupModel()
        model.configureScan(categories: [category], policyCategories: [category])
        model.finishScan(result)
        XCTAssertEqual(model.classification(for: item), .regenerable)
        let managed = FindingCategory(id: "managed", title: "Managed", explanation: "Fixture", location: category.location, classification: .manageExternally)
        model.configureScan(categories: [category], policyCategories: [managed])
        XCTAssertEqual(model.classification(for: item), .manageExternally)
        XCTAssertTrue(model.selectableItems([item]).isEmpty)
        model.configureScan(categories: [category], policyCategories: [])
        XCTAssertEqual(model.classification(for: item), .regenerable)
    }


    @MainActor
    func testSimulatorLabelsUseInventoryAndSavedMetadataWhilePreservingOriginalPath() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let deviceID = UUID().uuidString
        let orphanID = UUID().uuidString
        let device = folder.appendingPathComponent(deviceID)
        let orphan = folder.appendingPathComponent(orphanID)
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["name": "Renamed iPhone"], format: .binary, options: 0)
        try plist.write(to: device.appendingPathComponent("device.plist"))
        try Data("invalid plist".utf8).write(to: orphan.appendingPathComponent("device.plist"))
        let strayFile = folder.appendingPathComponent(UUID().uuidString)
        try Data("file".utf8).write(to: strayFile)
        let category = FindingCategory(id: "simulators", title: "Devices", explanation: "Device data", location: try FilesystemPath(folder), classification: .simulatorDevice)
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category]))
        let result = try await session.result()
        let item = try XCTUnwrap(result.item(at: FilesystemPath(device)))
        let orphanItem = try XCTUnwrap(result.item(at: FilesystemPath(orphan)))
        let local = await CleanupOperations.localSimulatorDetails([item, orphanItem]).mapValues(\.name)
        XCTAssertEqual(local, [deviceID: "Renamed iPhone"])
        let model = CleanupModel()
        model.configureScan(categories: [category], policyCategories: [category])
        model.applySimulatorInventory(names: [deviceID: "iPhone 17"])
        model.finishScan(result)
        defer { model.close() }
        XCTAssertEqual(model.displayName(item), "iPhone 17")
        XCTAssertEqual(model.displayName(orphanItem), "Unknown simulator")
        XCTAssertEqual(model.items(for: category).count, 2)
        XCTAssertNotNil(model.selectionUnavailableReason(item, classification: .simulatorDevice))
        model.applySimulatorInventory(names: local)
        XCTAssertEqual(model.displayName(item), "Renamed iPhone")
        XCTAssertEqual(item.path.displayName, deviceID)
    }

    func testRenamedSimulatorRetainsModelAndOSVersion() throws {
        let id = UUID().uuidString
        let data = Data("""
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-5":[
            {"udid":"\(id)","name":"My testing phone","state":"Shutdown","isAvailable":true,
             "deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"}]},
         "devicetypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro","name":"iPhone 16 Pro"}],
         "runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-5","name":"iOS 18.5"}]}
        """.utf8)
        let device = try XCTUnwrap(CleanupOperations.decodeSimulatorDevices(data).devices[id])
        XCTAssertEqual(device.name, "My testing phone")
        XCTAssertEqual(device.model, "iPhone 16 Pro")
        XCTAssertEqual(device.runtimeName, "iOS 18.5")
        XCTAssertEqual(CleanupOperations.simulatorRuntimeName("com.apple.CoreSimulator.SimRuntime.iOS-17-2-1"), "iOS 17.2.1")
        XCTAssertEqual(CleanupOperations.simulatorRuntimeName("com.apple.CoreSimulator.SimRuntime.xrOS-2-2"), "visionOS 2.2")
        XCTAssertEqual(CleanupOperations.simulatorRuntimeName("unrecognized"), "Unknown OS version")
    }

    func testSimulatorDeletionAllowsAvailableStoppedDevicesButRejectsRunningAndChangedAssociations() throws {
        let id = UUID().uuidString
        let selected = CleanupOperations.SimulatorXcode(developerDirectory: "/Selected", name: "Xcode 27", selected: true)
        let installed = CleanupOperations.SimulatorXcode(developerDirectory: "/Other", name: "Xcode 26", selected: false)
        for availability in [true, false] {
            let device = CleanupOperations.SimulatorDevice(id: id, name: "iPhone", runtime: "runtime", isAvailable: availability, state: "Shutdown")
            XCTAssertNoThrow(try CleanupOperations.validateSimulatorDeletion(id: id.lowercased(), inventory: .init(devices: [id: device])))
        }
        for state in ["Booted", "Booting", "Creating", "Unknown"] {
            let device = CleanupOperations.SimulatorDevice(id: id, name: "iPhone", runtime: "runtime", isAvailable: true, state: state)
            XCTAssertThrowsError(try CleanupOperations.validateSimulatorDeletion(id: id, inventory: .init(devices: [id: device])))
        }
        XCTAssertThrowsError(try CleanupOperations.validateSimulatorDeletion(id: id, inventory: .init(devices: [:])))
        let previous = CleanupOperations.SimulatorDevice(id: id, name: "Phone", runtime: "runtime", isAvailable: false, state: "Shutdown")
        let changed = CleanupOperations.SimulatorDevice(id: id, name: "Phone", runtime: "runtime", isAvailable: true, state: "Shutdown")
        XCTAssertThrowsError(try CleanupOperations.validateSimulatorRefresh(id: id,
            assessed: .init(devices: [id: previous]), fresh: .init(devices: [id: changed])))
        XCTAssertNoThrow(try CleanupOperations.validateSimulatorAssociations(current: [selected], confirmed: [selected, installed]))
        XCTAssertThrowsError(try CleanupOperations.validateSimulatorAssociations(current: [selected, installed], confirmed: [selected]))
        // Changing which Xcode is selected changes the warning and requires renewed confirmation.
        let newlySelected = CleanupOperations.SimulatorXcode(developerDirectory: "/Other", name: "Xcode 26", selected: true)
        XCTAssertThrowsError(try CleanupOperations.validateSimulatorAssociations(current: [newlySelected], confirmed: [installed]))
    }

    @MainActor
    func testSimulatorRowsAllowSelectionAndExplainInstalledXcodeAssociations() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let availableID = UUID().uuidString, obsoleteID = UUID().uuidString, bootedID = UUID().uuidString
        for id in [availableID, obsoleteID, bootedID] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(id), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let category = FindingCategory(id: "simulators", title: "Devices", explanation: "Device data", location: try FilesystemPath(folder), classification: .simulatorDevice)
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category]))
        let result = try await session.result()
        let availableItem = try XCTUnwrap(result.item(at: FilesystemPath(folder.appendingPathComponent(availableID))))
        let obsoleteItem = try XCTUnwrap(result.item(at: FilesystemPath(folder.appendingPathComponent(obsoleteID))))
        let bootedItem = try XCTUnwrap(result.item(at: FilesystemPath(folder.appendingPathComponent(bootedID))))
        let selected = CleanupOperations.SimulatorXcode(developerDirectory: "/Selected", name: "Xcode 27", selected: true)
        let installed = CleanupOperations.SimulatorXcode(developerDirectory: "/Other", name: "Xcode 26", selected: false)
        let available = CleanupOperations.SimulatorDevice(id: availableID, name: "My phone", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-5", model: "iPhone 16 Pro", runtimeName: "iOS 18.5", isAvailable: true, state: "Shutdown")
        let obsolete = CleanupOperations.SimulatorDevice(id: obsoleteID, name: "Old phone", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-15-0", isAvailable: false, state: "Shutdown")
        let booted = CleanupOperations.SimulatorDevice(id: bootedID, name: "Running phone", runtime: "runtime", isAvailable: true, state: "Booted")
        var assessment = CleanupOperations.SimulatorAssessment()
        assessment.include(.init(devices: [availableID: available, obsoleteID: obsolete, bootedID: booted]), xcode: selected)
        assessment.include(.init(devices: [availableID: available, obsoleteID: obsolete]), xcode: installed)
        let model = CleanupModel()
        model.configureScan(categories: [category], policyCategories: [category])
        model.applySimulatorAssessment(assessment)
        model.finishScan(result)
        defer { model.close() }
        XCTAssertNil(model.selectionUnavailableReason(availableItem, classification: .simulatorDevice))
        XCTAssertNil(model.selectionUnavailableReason(obsoleteItem, classification: .simulatorDevice))
        XCTAssertNotNil(model.selectionUnavailableReason(bootedItem, classification: .simulatorDevice))
        XCTAssertEqual(model.displayName(availableItem), "iPhone 16 Pro")
        XCTAssertEqual(model.operatingSystemLabel(availableItem), "iOS 18.5")
        model.selectedOperatingSystem = "iOS 15"
        XCTAssertEqual(model.visibleSections.flatMap(\.items).map(\.id), [obsoleteItem.id])
        model.toggleSelection(model.visibleSections[0].items)
        XCTAssertEqual(model.selected, [obsoleteItem.id])
        model.selectedOperatingSystem = nil
        XCTAssertTrue(model.selected.isEmpty)
        model.setSelected(obsoleteItem, selected: true)
        XCTAssertFalse(model.cleanupConfirmationMessage.contains("can be used by"))
        model.setSelected(availableItem, selected: true)
        XCTAssertTrue(model.cleanupConfirmationMessage.contains("selected Xcode 27"))
        XCTAssertTrue(model.cleanupConfirmationMessage.contains("installed Xcode 26"))
        XCTAssertEqual(model.selectedSimulatorAssociations[availableID], [selected, installed])
        XCTAssertTrue(model.cleanupConfirmationMessage.contains("permanently"))
        var unknown = assessment
        unknown.failedXcodes = [installed]
        model.applySimulatorAssessment(unknown)
        XCTAssertNotNil(model.selectionUnavailableReason(obsoleteItem, classification: .simulatorDevice))
        // An active state observed by one installation cannot be overwritten by another's Shutdown.
        assessment.include(.init(devices: [bootedID: .init(id: bootedID, name: "Phone", runtime: "runtime", isAvailable: true, state: "Shutdown")]), xcode: installed)
        XCTAssertEqual(assessment.devices[bootedID]?.state, "Booted")
    }

    @MainActor
    func testOSFilterTargetsMatchingArchivesAndSupportWithoutSelectingMixedParents() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archiveRoot = folder.appendingPathComponent("Archives")
        let date = archiveRoot.appendingPathComponent("2026-10-02")
        let old = date.appendingPathComponent("Old.xcarchive")
        let current = date.appendingPathComponent("Current.xcarchive")
        let supportRoot = folder.appendingPathComponent("iOS DeviceSupport")
        let support = supportRoot.appendingPathComponent("iPhone18,1 17.5 (build)")
        let backupsRoot = folder.appendingPathComponent("Backups")
        let backup = backupsRoot.appendingPathComponent("backup-id")
        func writePlist(_ values: [String: Any], to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0).write(to: url)
        }
        for (archive, version) in [(old, "17.5"), (current, "27.0")] {
            try writePlist(["ApplicationProperties": ["ApplicationPath": "Applications/App.app"]], to: archive.appendingPathComponent("Info.plist"))
            try writePlist(["DTPlatformName": "iphoneos", "DTPlatformVersion": version, "MinimumOSVersion": "15.0"],
                           to: archive.appendingPathComponent("Products/Applications/App.app/Info.plist"))
        }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try writePlist(["Product Version": "17.6.1"], to: backup.appendingPathComponent("Info.plist"))
        let categories = try [
            FindingCategory(id: "archives", title: "Archives", explanation: "Keep archives", location: FilesystemPath(archiveRoot), classification: .review),
            FindingCategory(id: "deviceSupport", title: "Support", explanation: "Support", location: FilesystemPath(supportRoot), classification: .regenerable),
            FindingCategory(id: "backups", title: "Backups", explanation: "Manage in Finder", location: FilesystemPath(backupsRoot), classification: .manageExternally)
        ]
        let session = try ScanSession(request: ScanRequest(roots: categories.map(\.location), categories: categories))
        let result = try await session.result()
        let oldItem = try XCTUnwrap(result.item(at: FilesystemPath(old)))
        let currentItem = try XCTUnwrap(result.item(at: FilesystemPath(current)))
        let dateItem = try XCTUnwrap(result.item(at: FilesystemPath(date)))
        let supportItem = try XCTUnwrap(result.item(at: FilesystemPath(support)))
        let backupItem = try XCTUnwrap(result.item(at: FilesystemPath(backup)))
        let requests = [(item: oldItem, category: "archives"), (item: currentItem, category: "archives"),
                        (item: supportItem, category: "deviceSupport"), (item: backupItem, category: "backups")]
        let versions = await CleanupOSMetadata.read(requests)
        XCTAssertEqual(versions[oldItem.id], "iOS 17.5")
        XCTAssertEqual(versions[currentItem.id], "iOS 27.0")
        XCTAssertEqual(versions[backupItem.id], "iOS 17.6.1")
        let model = CleanupModel()
        model.configureScan(categories: categories, policyCategories: categories)
        model.finishScan(result)
        defer { model.close() }
        model.applyOSMetadata(versions)
        XCTAssertEqual(model.operatingSystems, ["iOS 27", "iOS 17"])
        XCTAssertFalse(model.operatingSystems.contains("iOS 15"), "Archive filters use build OS, not minimum deployment target")
        XCTAssertEqual(model.visibleSections.first { $0.id == "category:archives" }?.items.map(\.id), [dateItem.id])
        model.setSelected(dateItem, selected: true)
        model.selectedOperatingSystem = "iOS 17"
        XCTAssertTrue(model.selected.isEmpty, "Changing filters clears hidden selections")
        XCTAssertEqual(model.visibleSections.count, 3)
        let archives = try XCTUnwrap(model.visibleSections.first { $0.id == "category:archives" })
        XCTAssertEqual(archives.items.map(\.id), [oldItem.id])
        XCTAssertEqual(archives.allocatedBytes, oldItem.allocatedBytes)
        model.toggleSelection(archives.items)
        XCTAssertEqual(model.selected, [oldItem.id])
        XCTAssertEqual(try result.normalizedSelection(Array(model.selected)).map(\.id), [oldItem.id])
        XCTAssertTrue(model.selectableItems([backupItem]).isEmpty)
        model.selectedOperatingSystem = "iOS 27"
        XCTAssertEqual(model.visibleSections.count, 1)
        XCTAssertEqual(model.visibleSections[0].items.map(\.id), [currentItem.id])
        model.selectedOperatingSystem = nil
        XCTAssertEqual(model.visibleSections.count, 3)
        XCTAssertEqual(model.visibleSections.first { $0.id == "category:archives" }?.items.map(\.id), [dateItem.id])
    }

    @MainActor
    func testRuntimeFilterSelectionSavingsAndManagedImageProtection() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("runtime.dmg")
        try Data("runtime image".utf8).write(to: image)
        let session = try ScanSession(request: ScanRequest(roots: [FilesystemPath(folder)]))
        let result = try await session.result()
        let item = try XCTUnwrap(result.item(at: FilesystemPath(image)))
        let root = try XCTUnwrap(result.item(at: FilesystemPath(folder)))
        let ios = CleanupOperations.SimulatorRuntime(identifier: UUID().uuidString, runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-5", build: "21F79", path: image.path, parentImagePath: nil, runtimeBundlePath: nil, sizeBytes: 100, deletable: true, state: "Ready")
        let vision = CleanupOperations.SimulatorRuntime(identifier: UUID().uuidString, runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.xrOS-26-0", build: "23M1", path: "/unused/vision.dmg", parentImagePath: nil, runtimeBundlePath: nil, sizeBytes: 200, deletable: true, state: "Ready")
        let xcode = CleanupOperations.SimulatorXcode(developerDirectory: "/Selected", name: "Xcode 27", selected: true)
        let model = CleanupModel()
        model.finishScan(result)
        defer { model.close() }
        model.applyRuntimeInventory([vision, ios], associations: [ios.id: [xcode]])
        XCTAssertEqual(model.operatingSystems, ["iOS 17", "visionOS 26"])
        XCTAssertNotNil(model.selectionUnavailableReason(item, classification: .review))
        XCTAssertNotNil(model.selectionUnavailableReason(root, classification: .review))
        XCTAssertEqual(model.totalScannedBytes, result.progress.allocatedBytes + 200, "Scanned image is not counted twice")
        model.selectedOperatingSystem = "iOS 17"
        XCTAssertEqual(model.visibleRuntimes.map(\.id), [ios.id])
        model.toggleRuntimeSelection()
        XCTAssertEqual(model.selectedCount, 1)
        XCTAssertEqual(model.estimatedSavingsBytes, 100)
        XCTAssertEqual(model.cleanupActionTitle, "Remove Runtimes")
        XCTAssertTrue(model.cleanupConfirmationMessage.contains("uninstalled"))
        XCTAssertTrue(model.cleanupConfirmationMessage.contains("selected Xcode 27"))
        XCTAssertEqual(model.selectedSimulatorAssociations["runtime:" + ios.id], [xcode])
        model.selectedOperatingSystem = "visionOS 26"
        XCTAssertTrue(model.selectedRuntimes.isEmpty)
        model.toggleRuntimeSelection()
        XCTAssertEqual(model.selectedRuntimes, [vision.id])
        model.applyRuntimeInventory([vision, ios], associations: [:], associationCheckFailed: true)
        XCTAssertNotNil(model.runtimeSelectionUnavailableReason(vision))
        model.applyRuntimeInventory([], associations: [:], unavailable: true)
        XCTAssertNotNil(model.selectionUnavailableReason(item, classification: .review))
        XCTAssertNotNil(model.runtimeSelectionUnavailableReason(ios))
        XCTAssertEqual(model.simulatorRuntimes.count, 2, "Failed inventories retain managed-path protection")
    }

    func testRuntimeRemovalRejectsActiveDevicesChangedImagesAndNonDeletableAssets() throws {
        let runtime = CleanupOperations.SimulatorRuntime(identifier: UUID().uuidString, runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-5", build: "21F79", path: "/image.dmg", parentImagePath: nil, runtimeBundlePath: nil, sizeBytes: 100, deletable: true, state: "Ready")
        let encoded = try JSONSerialization.data(withJSONObject: [runtime.id: [
            "identifier": runtime.identifier, "runtimeIdentifier": runtime.runtimeIdentifier, "build": runtime.build,
            "path": runtime.path, "sizeBytes": runtime.sizeBytes, "deletable": true, "state": "Ready"
        ]])
        XCTAssertEqual(try CleanupOperations.decodeSimulatorRuntimes(encoded), [runtime])
        let empty = CleanupOperations.SimulatorInventory(devices: [:])
        XCTAssertNoThrow(try CleanupOperations.validateRuntimeDeletion(runtime, fresh: [runtime], devices: empty))
        let device = CleanupOperations.SimulatorDevice(id: UUID().uuidString, name: "iPhone", runtime: runtime.runtimeIdentifier, isAvailable: true, state: "Booted")
        XCTAssertThrowsError(try CleanupOperations.validateRuntimeDeletion(runtime, fresh: [runtime], devices: .init(devices: [device.id: device])))
        XCTAssertThrowsError(try CleanupOperations.validateRuntimeDeletion(runtime, fresh: [], devices: empty))
        let changed = CleanupOperations.SimulatorRuntime(identifier: runtime.identifier, runtimeIdentifier: runtime.runtimeIdentifier, build: "different", path: runtime.path, parentImagePath: nil, runtimeBundlePath: nil, sizeBytes: 100, deletable: true, state: "Ready")
        XCTAssertThrowsError(try CleanupOperations.validateRuntimeDeletion(runtime, fresh: [changed], devices: empty))
        let protected = CleanupOperations.SimulatorRuntime(identifier: runtime.identifier, runtimeIdentifier: runtime.runtimeIdentifier, build: runtime.build, path: runtime.path, parentImagePath: nil, runtimeBundlePath: nil, sizeBytes: 100, deletable: false, state: "Ready")
        XCTAssertThrowsError(try CleanupOperations.validateRuntimeDeletion(runtime, fresh: [protected], devices: empty))
        let installing = CleanupOperations.SimulatorRuntime(identifier: runtime.identifier, runtimeIdentifier: runtime.runtimeIdentifier, build: runtime.build, path: runtime.path, parentImagePath: nil, runtimeBundlePath: nil, sizeBytes: 100, deletable: true, state: "Installing")
        XCTAssertThrowsError(try CleanupOperations.validateRuntimeDeletion(runtime, fresh: [installing], devices: empty))
    }

    func testOSMetadataParsesDeviceSupportNamesAndRejectsAmbiguousVersions() {
        XCTAssertEqual(CleanupOSMetadata.deviceSupportVersion("iPhone18,1 27.0 (24A435)"), "iOS 27.0")
        XCTAssertEqual(CleanupOSMetadata.deviceSupportVersion("18.5 (22F77)"), "iOS 18.5")
        XCTAssertNil(CleanupOSMetadata.deviceSupportVersion("iPhone18,1"))
        XCTAssertNil(CleanupOSMetadata.filterName("Unknown OS version"))
        XCTAssertEqual(CleanupOSMetadata.filterName("visionOS 26.5"), "visionOS 26")
    }

    @MainActor
    func testCleanupUpdatesRetainedResultsWithoutRescanningAndKeepsFailedSelections() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = folder.appendingPathComponent("project/node_modules")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8192).write(to: nested.appendingPathComponent("data"))
        let other = folder.appendingPathComponent("failed.txt")
        try Data(repeating: 2, count: 4096).write(to: other)
        defer { try? FileManager.default.removeItem(at: folder) }
        let category = FindingCategory(id: "custom", title: "Files", explanation: "Review", location: try FilesystemPath(folder), classification: .review)
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category], detectNodeModules: true))
        let result = try await session.result()
        let root = try XCTUnwrap(result.item(at: FilesystemPath(folder)))
        let project = try XCTUnwrap(result.item(at: FilesystemPath(folder.appendingPathComponent("project"))))
        let modules = try XCTUnwrap(result.item(at: FilesystemPath(nested)))
        let failed = try XCTUnwrap(result.item(at: FilesystemPath(other)))
        let model = CleanupModel()
        model.configureScan(categories: [category], policyCategories: [category])
        model.finishScan(result)
        defer { model.close() }
        model.selected = [modules.id, failed.id]
        model.applyCleanupOutcome(items: [modules.id], runtimes: [])
        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(model.result?.scanID, result.scanID)
        XCTAssertEqual(model.progress?.phase, .completed)
        XCTAssertEqual(model.selected, [failed.id])
        XCTAssertEqual(model.displayedBytes(for: project), project.allocatedBytes - modules.allocatedBytes)
        XCTAssertEqual(model.totalScannedBytes, result.progress.allocatedBytes - modules.allocatedBytes)
        XCTAssertFalse(model.sections.contains { $0.id.hasPrefix("finding:") })
        XCTAssertFalse(model.items(for: category).isEmpty)
        XCTAssertNotNil(result.item(modules.id), "The immutable shared scan remains queryable")
        // Removing a parent in a later batch replaces its already-removed child in the accounting.
        model.applyCleanupOutcome(items: [project.id], runtimes: [])
        XCTAssertEqual(model.totalScannedBytes, result.progress.allocatedBytes - project.allocatedBytes)
        XCTAssertEqual(model.sections.first?.items.map(\.id), [failed.id])
        XCTAssertEqual(model.sections.first?.allocatedBytes, root.allocatedBytes - project.allocatedBytes)
        XCTAssertEqual(model.selected, [failed.id])
        model.applyCleanupOutcome(items: [project.id], runtimes: [])
        XCTAssertEqual(model.totalScannedBytes, result.progress.allocatedBytes - project.allocatedBytes, "Duplicate outcomes cannot subtract twice")
    }

    @MainActor
    func testCleanupKeepsOSFilterAndRemovesOnlySuccessfulRuntimes() {
        let old = CleanupOperations.SimulatorRuntime(identifier: UUID().uuidString, runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-5", build: "21F79", path: "/old.dmg", parentImagePath: nil, runtimeBundlePath: nil, sizeBytes: 100, deletable: true, state: "Ready")
        let failed = CleanupOperations.SimulatorRuntime(identifier: UUID().uuidString, runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-0", build: "21A1", path: "/failed.dmg", parentImagePath: nil, runtimeBundlePath: nil, sizeBytes: 200, deletable: true, state: "Ready")
        let model = CleanupModel()
        model.applyRuntimeInventory([old, failed], associations: [:])
        model.selectedOperatingSystem = "iOS 17"
        model.toggleRuntimeSelection()
        XCTAssertEqual(model.selectedCount, 2)
        model.applyCleanupOutcome(items: [], runtimes: [old.id])
        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(model.selectedOperatingSystem, "iOS 17")
        XCTAssertEqual(model.selectedRuntimes, [failed.id])
        XCTAssertEqual(model.visibleRuntimes.map(\.id), [failed.id])
        XCTAssertEqual(model.totalScannedBytes, 200)
        XCTAssertEqual(model.estimatedSavingsBytes, 200)
        // CoreSimulator can echo a just-uninstalled image while it finishes removing assets.
        model.applyRuntimeInventory([old, failed], associations: [:])
        XCTAssertEqual(model.visibleRuntimes.map(\.id), [failed.id])
        XCTAssertEqual(model.totalScannedBytes, 200)
    }

    @MainActor
    func testFolderConfigurationPersistsAddRenameRelocateAndRemove() async throws {
        let storage = OSAllocatedUnfairLock(initialState: Data?.none)
        var defaults = Defaults()
        defaults.get = { key in key == "cleanup.scanFolders.v1" ? storage.withLock { $0 } : nil }
        defaults.set = { value, key in
            guard key == "cleanup.scanFolders.v1" else { return }
            let data = value as? Data; storage.withLock { $0 = data }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = root.appendingPathComponent("Projects")
        let replacement = root.appendingPathComponent("Other projects")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try Data("file".utf8).write(to: original.appendingPathComponent("one"))
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = CleanupFolder(id: UUID(), name: "Projects", url: original, preset: nil)
        let model = CleanupModel(defaults: defaults)
        XCTAssertTrue(model.folders.isEmpty)
        try model.replaceFolders([folder], rescan: false)
        let category = try folder.category()
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category]))
        let result = try await session.result()
        model.finishScan(result)
        defer { model.close() }
        XCTAssertEqual(model.sections.first?.id, "category:" + folder.categoryID)
        XCTAssertEqual(model.sections.first?.title, "Projects")
        var renamed = folder
        renamed.name = "  My projects  "
        try model.replaceFolders([renamed])
        XCTAssertFalse(model.isScanning, "Renaming a folder does not require another filesystem scan")
        XCTAssertEqual(model.result?.scanID, result.scanID)
        XCTAssertEqual(model.sections.first?.title, "My projects")
        XCTAssertEqual(model.sections.first?.id, "category:" + folder.categoryID)
        let reopened = CleanupModel(defaults: defaults)
        XCTAssertEqual(reopened.folders, model.folders)
        renamed.url = replacement
        try reopened.replaceFolders([renamed], rescan: false)
        XCTAssertEqual(CleanupModel(defaults: defaults).folders.first?.url.path, replacement.path)
        XCTAssertEqual(CleanupModel(defaults: defaults).folders.first?.id, folder.id)
        try reopened.replaceFolders([], rescan: false)
        XCTAssertTrue(CleanupModel(defaults: defaults).folders.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "Removing from scan settings never deletes the folder")
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.path))
    }

    @MainActor
    func testFolderConfigurationRejectsDuplicatesAndKeepsManagedPresetsProtected() throws {
        let storage = OSAllocatedUnfairLock(initialState: Data?.none)
        var defaults = Defaults()
        defaults.get = { key in key == "cleanup.scanFolders.v1" ? storage.withLock { $0 } : nil }
        defaults.set = { value, key in
            guard key == "cleanup.scanFolders.v1" else { return }
            let data = value as? Data; storage.withLock { $0 = data }
        }
        let model = CleanupModel(defaults: defaults)
        XCTAssertEqual(CleanupFolder.Preset.allCases, [.downloads, .backups, .appCaches, .trash, .npm, .cargo, .gradle, .docker])
        let home = URL(fileURLWithPath: "/fake-home")
        let presets = try CleanupFolder.Preset.allCases.map { try $0.folder(home: home) }
        let suggestions = try FindingCatalog.optional(home: home)
        for (folder, suggestion) in zip(presets, suggestions) {
            let category = try folder.category()
            XCTAssertEqual(folder.name, suggestion.title)
            XCTAssertEqual(folder.url, suggestion.location.url)
            XCTAssertEqual(category.explanation, suggestion.explanation)
            XCTAssertEqual(category.classification, suggestion.classification)
        }
        var customized = presets[0]
        customized.name = "My downloads"
        customized.url = home.appendingPathComponent("custom-downloads")
        XCTAssertEqual(try customized.category().title, "My downloads")
        XCTAssertEqual(try customized.category().location.url, customized.url)
        try model.replaceFolders(presets, rescan: false)
        XCTAssertEqual(model.folders.count, CleanupFolder.Preset.allCases.count)
        XCTAssertEqual(try presets[1].category().classification, .manageExternally)
        XCTAssertEqual(try presets[3].category().classification, .manageExternally)
        XCTAssertEqual(try presets[0].category().classification, .review)
        let duplicate = CleanupFolder(id: UUID(), name: "Same downloads", url: home.appendingPathComponent("Downloads/../Downloads"), preset: nil)
        XCTAssertThrowsError(try model.replaceFolders(presets + [duplicate], rescan: false))
        XCTAssertEqual(model.folders, presets)
        let invalid = CleanupFolder(id: UUID(), name: "Remote", url: URL(string: "https://example.com")!, preset: nil)
        XCTAssertThrowsError(try model.replaceFolders([invalid], rescan: false))
        XCTAssertEqual(CleanupModel(defaults: defaults).folders, presets, "Rejected changes must not overwrite saved folders")
    }

    @MainActor
    func testAddedBackupFolderParticipatesInOSFilteringAndRemainsReviewOnly() async throws {
        var defaults = Defaults()
        defaults.get = { _ in nil }; defaults.set = { _, _ in }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backup = root.appendingPathComponent("device-backup")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try PropertyListSerialization.data(fromPropertyList: ["Product Version": "17.5"], format: .binary, options: 0)
            .write(to: backup.appendingPathComponent("Info.plist"))
        var folder = try CleanupFolder.Preset.backups.folder()
        folder.name = "My backups"; folder.url = root
        let model = CleanupModel(defaults: defaults)
        try model.replaceFolders([folder], rescan: false)
        let category = try folder.category()
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category]))
        let result = try await session.result()
        model.finishScan(result)
        defer { model.close() }
        let item = try XCTUnwrap(result.item(at: FilesystemPath(backup)))
        model.applyOSMetadata(await CleanupOSMetadata.read([(item: item, category: "backups")]))
        model.selectedOperatingSystem = "iOS 17"
        XCTAssertEqual(model.visibleSections.first?.items.map(\.id), [item.id])
        XCTAssertEqual(model.visibleSections.first?.id, "category:" + folder.categoryID)
        XCTAssertEqual(model.visibleSections.first?.osCategory, "backups")
        XCTAssertEqual(model.classification(for: item), .manageExternally)
        XCTAssertTrue(model.selectableItems([item]).isEmpty)
    }

    @MainActor
    func testAllScanFoldersIncludeDeveloperRootsAndPersistTheirRemoval() throws {
        let storage = OSAllocatedUnfairLock(initialState: (data: Data?.none, exclusions: [String]()))
        var defaults = Defaults()
        defaults.get = { key in
            let saved = storage.withLock { $0 }
            return key.contains("excludedFolders") ? saved.exclusions : saved.data
        }
        defaults.set = { value, key in
            let data = value as? Data; let exclusions = value as? [String]
            storage.withLock { saved in
                if key.contains("excludedFolders") { saved.exclusions = exclusions ?? [] }
                else { saved.data = data }
            }
        }
        let model = CleanupModel(defaults: defaults)
        XCTAssertTrue(model.scanFolders.contains { $0.categoryID == "derivedData" })
        XCTAssertTrue(model.scanFolders.contains { $0.categoryID == "simulators" })
        XCTAssertTrue(model.scanFolders.contains { $0.categoryID == "simulatorRuntimes" })
        let original = model.scanFolders
        try model.replaceScanFolders(original.filter { !["derivedData", "simulatorRuntimes"].contains($0.categoryID) })
        XCTAssertFalse(model.isScanning, "Changing settings with the cleanup window closed must not start a scan")
        XCTAssertFalse(model.scanFolders.contains { $0.categoryID == "derivedData" })
        XCTAssertFalse(model.scanFolders.contains { $0.categoryID == "simulatorRuntimes" })
        let reopened = CleanupModel(defaults: defaults)
        XCTAssertEqual(reopened.scanFolders, model.scanFolders)
        XCTAssertEqual(reopened.excludedFolders, ["derivedData", "simulatorRuntimes"])
        try reopened.replaceScanFolders(original)
        XCTAssertTrue(CleanupModel(defaults: defaults).excludedFolders.isEmpty)
        XCTAssertEqual(CleanupModel(defaults: defaults).scanFolders, original)
        try reopened.replaceScanFolders([])
        XCTAssertTrue(reopened.scanFolders.isEmpty)
        XCTAssertFalse(reopened.isScanning)
    }

    @MainActor
    func testRemovedFolderScopeDoesNotKeepNestedCacheFindings() async throws {
        var defaults = Defaults(); defaults.get = { _ in nil }; defaults.set = { _, _ in }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = CleanupFolder(id: UUID(), name: "Project", url: root, preset: nil)
        let model = CleanupModel(defaults: defaults)
        try model.replaceScanFolders([folder], rescan: false)
        let category = try folder.category()
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category], detectNodeModules: true))
        model.finishScan(try await session.result())
        defer { model.close() }
        XCTAssertTrue(model.sections.contains { $0.id.hasPrefix("finding:") })
        try model.replaceScanFolders([], rescan: false)
        XCTAssertTrue(model.sections.isEmpty)
        XCTAssertTrue(model.scanFolders.isEmpty)
    }

    @MainActor
    func testUnreadableFolderShowsUnavailableRatherThanAnEmptySize() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let category = FindingCategory(id: "trash", title: "Trash", explanation: "Review only", location: try FilesystemPath(missing), classification: .manageExternally)
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category]))
        let model = CleanupModel()
        model.configureScan(categories: [category], policyCategories: [category])
        model.finishScan(try await session.result())
        let section = try XCTUnwrap(model.sections.first)
        XCTAssertTrue(section.incomplete)
        XCTAssertFalse(section.accessDenied, "A missing folder should not prompt for Full Disk Access")
        XCTAssertEqual(CleanupSectionData.sizeLabel(bytes: section.allocatedBytes, incomplete: section.incomplete), "Size unavailable")
        XCTAssertNotEqual(CleanupSectionData.sizeLabel(bytes: 0, incomplete: false), "Size unavailable", "A measured empty folder is different from an unreadable one")
    }

    @MainActor
    func testPermissionFailuresStayWithTheirFolderCategory() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let denied = folder.appendingPathComponent("restricted")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: denied.appendingPathComponent("file"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let category = FindingCategory(id: "restricted", title: "Folder", explanation: "", location: try FilesystemPath(folder), classification: .review)
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category]))
        let result = try await session.result()
        let restricted = try XCTUnwrap(result.item(at: FilesystemPath(denied)))
        XCTAssertEqual(restricted.status, .inaccessible)
        XCTAssertTrue(restricted.isAccessDenied)
        let model = CleanupModel()
        model.configureScan(categories: [category], policyCategories: [category])
        model.finishScan(result)
        XCTAssertTrue(try XCTUnwrap(model.sections.first).accessDenied, "An unreadable descendant must be reported on its collapsed category")
    }

    @MainActor
    func testScanDepthDefaultsToOneAndPersistsUnlimited() throws {
        let storage = OSAllocatedUnfairLock(initialState: [String: Int]())
        var defaults = Defaults()
        defaults.get = { key in storage.withLock { $0[key] } }
        defaults.set = { value, key in
            if let depth = value as? Int { storage.withLock { $0[key] = depth } }
        }
        let model = CleanupModel(defaults: defaults)
        XCTAssertEqual(model.scanDepth, 1)
        model.setScanDepth(5, rescan: false)
        XCTAssertEqual(CleanupModel(defaults: defaults).scanDepth, 5)
        model.setScanDepth(0, rescan: false)
        XCTAssertEqual(CleanupModel(defaults: defaults).scanDepth, 0)
        model.setScanDepth(-1, rescan: false)
        XCTAssertEqual(model.scanDepth, 0)
    }

    @MainActor
    func testDepthLimitedFoldersArePartialAndCannotBeSelectedForCleanup() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let child = folder.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: child.appendingPathComponent("file"))
        defer { try? FileManager.default.removeItem(at: folder) }
        let category = FindingCategory(id: "limited", title: "Folder", explanation: "", location: try FilesystemPath(folder), classification: .review)
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category], maximumDepth: 1))
        let result = try await session.result()
        let model = CleanupModel()
        model.configureScan(categories: [category], policyCategories: [category])
        model.finishScan(result)
        let section = try XCTUnwrap(model.sections.first)
        XCTAssertTrue(section.incomplete)
        XCTAssertFalse(section.accessDenied)
        let item = try XCTUnwrap(result.item(at: FilesystemPath(child)))
        XCTAssertTrue(model.selectionUnavailableReason(item, classification: .review)?.contains("depth") == true)
        model.setSelected(item, selected: true)
        XCTAssertTrue(model.selected.isEmpty)
        XCTAssertTrue(CleanupSectionData.sizeLabel(bytes: 1000, incomplete: true).contains("partial"))
    }

    @MainActor
    func testStartupScanContinuesWhenCleanupWindowCloses() {
        var defaults = Defaults(); defaults.get = { _ in nil }; defaults.set = { _, _ in }
        let model = CleanupModel(defaults: defaults)
        let appState = AppState()
        model.start(appState: appState)
        XCTAssertTrue(model.isScanning)
        XCTAssertNil(model.availableCleanupBytes)
        model.start(appState: appState)
        model.open(appState: appState)
        model.close()
        XCTAssertTrue(model.isScanning, "Closing the cleanup window must leave the app's scan running")
        model.cancelScan()
        XCTAssertFalse(model.isScanning)
        XCTAssertNil(model.availableCleanupBytes)
    }

    @MainActor
    func testAvailableCleanupTotalDeduplicatesAndUpdatesWithoutSelectionOrRescan() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("project")
        let managed = root.appendingPathComponent("managed")
        for directory in [project, managed] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 7, count: 40_000).write(to: directory.appendingPathComponent("file"))
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let categories = try [
            FindingCategory(id: "parent", title: "Parent", explanation: "", location: FilesystemPath(root), classification: .review),
            FindingCategory(id: "project", title: "Project", explanation: "", location: FilesystemPath(project), classification: .review),
            FindingCategory(id: "managed", title: "Managed", explanation: "", location: FilesystemPath(managed), classification: .manageExternally)
        ]
        let session = try ScanSession(request: ScanRequest(roots: categories.map(\.location), categories: categories))
        let result = try await session.result()
        let item = try XCTUnwrap(result.item(at: FilesystemPath(project)))
        let model = CleanupModel()
        model.configureScan(categories: categories, policyCategories: categories)
        model.receiveScanProgress(result)
        XCTAssertNil(model.availableCleanupBytes, "Progress must not publish a completed total")
        model.finishScan(result)
        XCTAssertEqual(model.availableCleanupBytes, item.allocatedBytes, "Exclude managed-only storage and count overlapping folders once")
        model.selectedOperatingSystem = "iOS 1"
        XCTAssertEqual(model.availableCleanupBytes, item.allocatedBytes, "The main-window total must not follow cleanup filters")
        model.applyCleanupOutcome(items: [item.id], runtimes: [])
        XCTAssertEqual(model.availableCleanupBytes, 0)
        XCTAssertEqual(model.result?.scanID, result.scanID)
    }

    @MainActor
    func testCachedResultsRestoreImmediatelyAndRefreshWithoutDiscardingAmount() async throws {
        let storage = OSAllocatedUnfairLock(initialState: [String: Data]())
        var defaults = Defaults()
        defaults.get = { key in storage.withLock { $0[key] } }
        defaults.set = { value, key in
            let data = value as? Data
            storage.withLock { $0[key] = data }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 40_000).write(to: root.appendingPathComponent("file"))
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = CleanupFolder(id: UUID(), name: "Fixture", url: root, preset: nil)
        let category = try folder.category()
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category]))
        let result = try await session.result()
        let model = CleanupModel(defaults: defaults)
        try model.replaceFolders([folder], rescan: false)
        model.configureScan(categories: [category], policyCategories: [category])
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        model.finishScan(result, completedAt: completedAt)
        let amount = try XCTUnwrap(model.availableCleanupBytes)
        let cached = CleanupModel(defaults: defaults)
        XCTAssertEqual(cached.lastScanCompletedAt, completedAt)
        XCTAssertEqual(cached.availableCleanupBytes, amount)
        XCTAssertEqual(cached.totalScannedBytes, model.totalScannedBytes)
        XCTAssertEqual(cached.sections.first?.title, "Fixture")
        XCTAssertTrue(cached.isShowingCachedResults)
        XCTAssertNil(cached.result, "Cached presentation is not authority for filesystem operations")
        let item = try XCTUnwrap(cached.sections.first?.items.first)
        cached.setSelected(item, selected: true)
        XCTAssertTrue(cached.selected.isEmpty)
        cached.start(appState: AppState())
        XCTAssertTrue(cached.isScanning)
        XCTAssertEqual(cached.availableCleanupBytes, amount)
        cached.cancelScan()
        XCTAssertEqual(cached.availableCleanupBytes, amount)
        let refreshedAt = completedAt.addingTimeInterval(60)
        cached.finishScan(result, completedAt: refreshedAt)
        XCTAssertFalse(cached.isShowingCachedResults)
        cached.applyCleanupOutcome(items: [item.id], runtimes: [])
        XCTAssertEqual(CleanupModel(defaults: defaults).availableCleanupBytes, 0)
        XCTAssertEqual(CleanupModel(defaults: defaults).lastScanCompletedAt, refreshedAt, "Cleanup must preserve the scan completion time")
        cached.setScanDepth(5, rescan: false)
        XCTAssertNil(CleanupModel(defaults: defaults).availableCleanupBytes, "Changing scan scope invalidates persisted results")
        storage.withLock { $0["cleanup.results.v1"] = Data("broken cache".utf8) }
        XCTAssertNil(CleanupModel(defaults: defaults).availableCleanupBytes)
    }

    @MainActor
    func testThirdPartyCachesAreOptInRatherThanDefaultFolders() throws {
        var defaults = Defaults(); defaults.get = { _ in nil }; defaults.set = { _, _ in }
        let model = CleanupModel(defaults: defaults)
        let optionalIDs: Set<String> = ["npm", "cargo", "gradle", "docker"]
        XCTAssertTrue(optionalIDs.isDisjoint(with: Set(model.scanFolders.map(\.categoryID))))
        let home = URL(fileURLWithPath: "/fixture-home")
        let folders = try [CleanupFolder.Preset.npm, .cargo, .gradle, .docker].map { try $0.folder(home: home) }
        XCTAssertEqual(folders.map(\.url.path), [
            "/fixture-home/.npm/_cacache", "/fixture-home/.cargo/registry",
            "/fixture-home/.gradle/caches", "/fixture-home/Library/Containers/com.docker.docker"
        ])
        XCTAssertEqual(folders.last?.classification, .manageExternally)
        try model.replaceScanFolders(model.scanFolders + folders, rescan: false)
        XCTAssertTrue(folders.allSatisfy { folder in model.scanFolders.contains { $0.id == folder.id } })
    }

    @MainActor
    func testFolderJSONMigratesPreferencesAndLoadsManualEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = root.appendingPathComponent("cleanup-folders.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = CleanupFolder(id: UUID(), name: "Projects", url: root.appendingPathComponent("projects"), preset: nil)
        let legacy = try JSONEncoder().encode([folder])
        var defaults = Defaults()
        defaults.get = { key in
            if key == "cleanup.scanFolders.v1" { return legacy }
            if key == "cleanup.scanDepth.v1" { return 5 }
            if key == "cleanup.excludedFolders.v1" { return ["derivedData"] }
            return nil
        }
        defaults.set = { _, _ in }
        let model = CleanupModel(defaults: defaults, folderConfigurationURL: file)
        let config = try JSONDecoder().decode(CleanupFolder.Configuration.self, from: Data(contentsOf: file))
        XCTAssertEqual(config.scanDepth, 5)
        XCTAssertEqual(config.folders.first?.path, folder.url.path)
        XCTAssertFalse(config.developerFolders.contains("derivedData"))
        XCTAssertNotNil(config._comment)
        let manual = Data("""
        {"version":1,"scanDepth":2,"developerFolders":["archives"],
         "folders":[{"path":"/fixture/manual-projects","name":"Manual projects"}]}
        """.utf8)
        try manual.write(to: file)
        try model.reloadFolderConfiguration()
        XCTAssertEqual(model.scanDepth, 2)
        XCTAssertEqual(model.scanFolders.map(\.name), ["Xcode archives", "Manual projects"])
        let restored = CleanupModel(defaults: defaults, folderConfigurationURL: file)
        XCTAssertEqual(restored.folders, model.folders, "Entries without IDs must receive stable identities")
        XCTAssertEqual(try Data(contentsOf: file), manual, "Reading manual edits must not rewrite the file")
        try Data("invalid JSON".utf8).write(to: file)
        XCTAssertThrowsError(try model.reloadFolderConfiguration())
        XCTAssertEqual(model.folders, restored.folders)
        XCTAssertEqual(try Data(contentsOf: file), Data("invalid JSON".utf8))
    }

    @MainActor
    func testJSONConfigurationPreservesCachedResultsAcrossLaunches() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = root.appendingPathComponent("config/cleanup-folders.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 40_000).write(to: root.appendingPathComponent("file"))
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = OSAllocatedUnfairLock(initialState: [String: Data]())
        var defaults = Defaults()
        defaults.get = { key in storage.withLock { $0[key] } }
        defaults.set = { value, key in let data = value as? Data; storage.withLock { $0[key] = data } }
        let model = CleanupModel(defaults: defaults, folderConfigurationURL: file)
        let folder = CleanupFolder(id: UUID(), name: "Fixture", url: root, preset: nil)
        try model.replaceFolders([folder], rescan: false)
        let category = try folder.category()
        let session = try ScanSession(request: ScanRequest(roots: [category.location], categories: [category]))
        model.configureScan(categories: [category], policyCategories: [category])
        model.finishScan(try await session.result())
        let restored = CleanupModel(defaults: defaults, folderConfigurationURL: file)
        XCTAssertEqual(restored.availableCleanupBytes, model.availableCleanupBytes)
        XCTAssertTrue(restored.isShowingCachedResults)
        XCTAssertEqual(restored.folders, model.folders)
        XCTAssertTrue(restored.setScanDepth(2, rescan: false))
        XCTAssertEqual(try JSONDecoder().decode(CleanupFolder.Configuration.self, from: Data(contentsOf: file)).scanDepth, 2)
    }

    @MainActor
    func testFolderConfigurationWriteFailureDoesNotPublishChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        defer { try? FileManager.default.removeItem(at: root) }
        var defaults = Defaults(); defaults.get = { _ in nil }; defaults.set = { _, _ in }
        let model = CleanupModel(defaults: defaults, folderConfigurationURL: blocked.appendingPathComponent("cleanup-folders.json"))
        let folder = CleanupFolder(id: UUID(), name: "Fixture", url: root, preset: nil)
        XCTAssertThrowsError(try model.replaceFolders([folder], rescan: false))
        XCTAssertTrue(model.folders.isEmpty)
        XCTAssertFalse(model.setScanDepth(5, rescan: false))
        XCTAssertEqual(model.scanDepth, 1)
    }

    @MainActor
    func testAppDefaultFoldersComeDirectlyFromPackageCatalog() throws {
        var defaults = Defaults(); defaults.get = { _ in nil }; defaults.set = { _, _ in }
        let model = CleanupModel(defaults: defaults)
        let catalog = try FindingCatalog.developer(home: FileManager.default.homeDirectoryForCurrentUser,
            xcodesDownloads: URL(fileURLWithPath: "/fixture-downloads"))
        XCTAssertEqual(model.suggestedDeveloperFolders.map(\.categoryID), catalog.map(\.id))
        XCTAssertEqual(model.suggestedDeveloperFolders.map(\.name), catalog.map(\.title))
        XCTAssertEqual(model.suggestedDeveloperFolders.map(\.id), CleanupModel(defaults: defaults).suggestedDeveloperFolders.map(\.id))
    }

    private static func cleanupProgressFixture() async throws -> (root: URL, result: ScanResult, items: [ScanItem]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["first", "second"] { try Data("fixture".utf8).write(to: root.appendingPathComponent(name)) }
        let session = try ScanSession(request: ScanRequest(roots: [FilesystemPath(root)]))
        let result = try await session.result()
        return (root, result, result.children(of: result.rootIDs[0]).sorted { $0.displayName < $1.displayName })
    }

    @MainActor
    func testCleanupContinuesAfterWindowClosesAndPublishesProgress() async throws {
        let fixture = try await Self.cleanupProgressFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = CleanupModel()
        model.finishScan(fixture.result)
        let gate = AsyncStream<Void>.makeStream()
        let started = expectation(description: "First operation started")
        var performed: [ScanItemID] = []
        model.startCleanup(items: fixture.items, runtimes: [], performItem: { item in
            performed.append(item.id)
            if performed.count == 1 {
                started.fulfill()
                for await _ in gate.stream { break }
            }
        }, performRuntime: { _ in XCTFail("No runtimes selected") })
        let task = try XCTUnwrap(model.cleanupTask)
        defer { gate.continuation.finish(); model.cleanupNoticeTask?.cancel() }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(model.cleanupProgress?.statusText, "Moving 1 of 2 to Trash…")
        XCTAssertEqual(model.cleanupProgress?.currentName, "first")
        XCTAssertEqual(model.cleanupProgress?.currentPath, fixture.items[0].path.displayPath)
        model.close()
        XCTAssertTrue(model.isCleaning)
        XCTAssertFalse(task.isCancelled)
        gate.continuation.yield(())
        await task.value
        XCTAssertEqual(performed, fixture.items.map(\.id))
        XCTAssertEqual(model.cleanupProgress?.completedCount, 2)
        XCTAssertEqual(model.cleanupProgress?.statusText, "Moved 2 items to Trash")
        XCTAssertTrue(model.cleanupProgress?.isFinished == true)
        XCTAssertFalse(model.isCleaning)
        XCTAssertEqual(model.result?.scanID, fixture.result.scanID)
        XCTAssertNil(model.message)
    }

    @MainActor
    func testStopCleanupFinishesCurrentItemAndLeavesRemainingSelection() async throws {
        let fixture = try await Self.cleanupProgressFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = CleanupModel()
        model.finishScan(fixture.result)
        model.selected = Set(fixture.items.map(\.id))
        let gate = AsyncStream<Void>.makeStream()
        let started = expectation(description: "Current operation started")
        var performed: [ScanItemID] = []
        let runtime = CleanupOperations.SimulatorRuntime(identifier: UUID().uuidString,
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-0", build: "test", path: "/fixture/runtime",
            parentImagePath: nil, runtimeBundlePath: nil, sizeBytes: 1, deletable: true, state: "Ready")
        model.startCleanup(items: fixture.items, runtimes: [runtime], performItem: { item in
            performed.append(item.id)
            started.fulfill()
            for await _ in gate.stream { break }
        }, performRuntime: { _ in XCTFail("Stop must also skip runtimes") })
        let task = try XCTUnwrap(model.cleanupTask)
        defer { gate.continuation.finish(); model.cleanupNoticeTask?.cancel() }
        await fulfillment(of: [started], timeout: 3)
        model.stopCleanupAfterCurrentItem()
        model.close()
        XCTAssertTrue(model.isCleaning)
        XCTAssertFalse(task.isCancelled)
        XCTAssertEqual(model.cleanupProgress?.statusText, "Stopping after current item…")
        gate.continuation.yield(())
        await task.value
        XCTAssertEqual(performed, [fixture.items[0].id])
        XCTAssertEqual(model.selected, [fixture.items[1].id])
        XCTAssertEqual(model.cleanupProgress?.completedCount, 1)
        XCTAssertEqual(model.cleanupProgress?.statusText, "Stopped · 1 of 3 processed")
        XCTAssertTrue(model.isCleaned(fixture.items[0]))
        XCTAssertFalse(model.isCleaned(fixture.items[1]))
    }

    @MainActor
    func testCleanupFailureAdvancesProgressAndRemainsAvailableForReview() async throws {
        let fixture = try await Self.cleanupProgressFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = CleanupModel()
        model.finishScan(fixture.result)
        model.selected = Set(fixture.items.map(\.id))
        model.startCleanup(items: fixture.items, runtimes: [], performItem: { item in
            if item.id == fixture.items[0].id { throw CleanupOperationError.changed }
        }, performRuntime: { _ in XCTFail("No runtimes selected") })
        let task = try XCTUnwrap(model.cleanupTask)
        await task.value
        XCTAssertEqual(model.cleanupProgress?.completedCount, 2)
        XCTAssertEqual(model.cleanupProgress?.movedCount, 1)
        XCTAssertEqual(model.cleanupProgress?.failureCount, 1)
        XCTAssertEqual(model.cleanupProgress?.statusText, "Cleanup finished · 1 failed")
        XCTAssertEqual(model.selected, [fixture.items[0].id])
        XCTAssertTrue(try XCTUnwrap(model.message).contains("first"))
        XCTAssertNil(model.cleanupNoticeTask, "Failures stay visible until reviewed")
        XCTAssertFalse(model.isCleaned(fixture.items[0]))
        XCTAssertTrue(model.isCleaned(fixture.items[1]))
    }

    @MainActor
    func testOrdinaryCleanupSkipsCoreSimulatorRefreshButStillValidatesAndChecksActivity() async throws {
        let fixture = try await Self.cleanupProgressFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = CleanupModel()
        model.finishScan(fixture.result)
        let xcode = CleanupOperations.SimulatorXcode(developerDirectory: "/fixture/Xcode.app/Contents/Developer", name: "Fixture Xcode", selected: false)
        model.simulatorAssessment = .init(failedXcodes: [xcode])
        model.runtimeInventoryUnavailable = true
        model.activityUnavailable = true
        model.selected = Set(fixture.items.map(\.id))
        // Replace one scanned inode. The remaining target should still reach the injected Trash operation.
        let replaced = fixture.items[0].path.url
        try FileManager.default.moveItem(at: replaced, to: fixture.root.appendingPathComponent("original"))
        try Data("replacement".utf8).write(to: replaced)
        let calls = OSAllocatedUnfairLock(initialState: [URL]())
        var files = Files()
        files.trashItem = { url in calls.withLock { $0.append(url) }; return url }
        model.cleanSelected(confirmedAssociations: [:], files: files)
        let task = try XCTUnwrap(model.cleanupTask)
        defer { model.cleanupNoticeTask?.cancel() }
        await task.value
        XCTAssertFalse(model.activityUnavailable, "The fast path must still check running processes")
        XCTAssertEqual(model.simulatorAssessment?.failedXcodes, [xcode], "Ordinary cleanup must leave simulator inventory untouched")
        XCTAssertTrue(model.runtimeInventoryUnavailable)
        XCTAssertEqual(calls.withLock { $0 }, [fixture.items[1].path.url])
        XCTAssertEqual(model.cleanupProgress?.movedCount, 1)
        XCTAssertEqual(model.cleanupProgress?.failureCount, 1)
        XCTAssertTrue(try XCTUnwrap(model.message).contains("changed or disappeared"))
        XCTAssertEqual(model.selected, [fixture.items[0].id])
    }

}
