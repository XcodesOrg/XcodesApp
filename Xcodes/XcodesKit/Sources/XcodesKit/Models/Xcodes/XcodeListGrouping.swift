import Foundation
@preconcurrency import Version

public enum XcodeListVersionFilter: Equatable, Sendable {
    case all
    case release
    case prerelease
}

public struct XcodeListFilters: Equatable, Sendable {
    public let versionFilter: XcodeListVersionFilter
    public let architectureFilters: [ArchitectureFilter]
    public let allowedMajorVersions: Int?
    public let searchText: String
    public let installedOnly: Bool

    public init(
        versionFilter: XcodeListVersionFilter = .all,
        architectureFilters: [ArchitectureFilter] = [],
        allowedMajorVersions: Int? = nil,
        searchText: String = "",
        installedOnly: Bool = false
    ) {
        self.versionFilter = versionFilter
        self.architectureFilters = architectureFilters
        self.allowedMajorVersions = allowedMajorVersions
        self.searchText = searchText
        self.installedOnly = installedOnly
    }
}

public struct XcodeMinorVersionGroup: Identifiable, Sendable {
    public let majorVersion: Int
    public let minorVersion: Int
    public let versions: [XcodeListItem]

    public var id: String {
        "\(majorVersion).\(minorVersion)"
    }

    public var latestRelease: XcodeListItem? {
        versions.latestRelease
    }

    public var displayName: String {
        "\(majorVersion).\(minorVersion)"
    }

    public var hasInstalled: Bool {
        versions.contains { $0.installState.installed }
    }

    public var hasInstalling: Bool {
        versions.contains { $0.installState.installing }
    }

    public var selectedVersion: XcodeListItem? {
        versions.first { $0.selected }
    }

    public init(majorVersion: Int, minorVersion: Int, versions: [XcodeListItem]) {
        self.majorVersion = majorVersion
        self.minorVersion = minorVersion
        self.versions = versions
    }
}

public struct XcodeMajorVersionGroup: Identifiable, Sendable {
    public let majorVersion: Int
    public let minorVersionGroups: [XcodeMinorVersionGroup]

    public var id: Int {
        majorVersion
    }

    public var versions: [XcodeListItem] {
        minorVersionGroups.flatMap(\.versions)
    }

    public var latestRelease: XcodeListItem? {
        versions.latestRelease
    }

    public var displayName: String {
        "\(majorVersion)"
    }

    public var hasInstalled: Bool {
        minorVersionGroups.contains { $0.hasInstalled }
    }

    public var hasInstalling: Bool {
        minorVersionGroups.contains { $0.hasInstalling }
    }

    public var selectedVersion: XcodeListItem? {
        minorVersionGroups.compactMap(\.selectedVersion).first
    }

    public init(majorVersion: Int, minorVersionGroups: [XcodeMinorVersionGroup]) {
        self.majorVersion = majorVersion
        self.minorVersionGroups = minorVersionGroups
    }
}

public struct XcodeListElementMinorVersionGroup<Element>: Identifiable {
    public let majorVersion: Int
    public let minorVersion: Int
    public let versions: [Element]

    public var id: String {
        "\(majorVersion).\(minorVersion)"
    }

    public var displayName: String {
        "\(majorVersion).\(minorVersion)"
    }

    public init(majorVersion: Int, minorVersion: Int, versions: [Element]) {
        self.majorVersion = majorVersion
        self.minorVersion = minorVersion
        self.versions = versions
    }
}

public struct XcodeListElementMajorVersionGroup<Element>: Identifiable {
    public let majorVersion: Int
    public let minorVersionGroups: [XcodeListElementMinorVersionGroup<Element>]

    public var id: Int {
        majorVersion
    }

    public var versions: [Element] {
        minorVersionGroups.flatMap(\.versions)
    }

    public var displayName: String {
        "\(majorVersion)"
    }

    public init(majorVersion: Int, minorVersionGroups: [XcodeListElementMinorVersionGroup<Element>]) {
        self.majorVersion = majorVersion
        self.minorVersionGroups = minorVersionGroups
    }
}

public extension Array {
    func applying(_ filters: XcodeListFilters, item: (Element) -> XcodeListItem) -> [Element] {
        let filteredItems = map { element in
            XcodeListFilteredElement(element: element, item: item(element))
        }
        .applying(filters)

        return filteredItems.map(\.element)
    }

    func groupedByMajorVersion(item: (Element) -> XcodeListItem) -> [XcodeListElementMajorVersionGroup<Element>] {
        Dictionary(grouping: self, by: { item($0).version.major })
            .map { majorVersion, elements in
                let minorVersionGroups = Dictionary(grouping: elements, by: { item($0).version.minor })
                    .map { minorVersion, minorElements in
                        XcodeListElementMinorVersionGroup(
                            majorVersion: majorVersion,
                            minorVersion: minorVersion,
                            versions: minorElements.sorted { item($0).version > item($1).version }
                        )
                    }
                    .sorted { $0.minorVersion > $1.minorVersion }

                return XcodeListElementMajorVersionGroup(
                    majorVersion: majorVersion,
                    minorVersionGroups: minorVersionGroups
                )
            }
            .sorted { $0.majorVersion > $1.majorVersion }
    }
}

public extension Array where Element == XcodeListItem {
    func applying(_ filters: XcodeListFilters) -> [XcodeListItem] {
        var items = self

        switch filters.versionFilter {
        case .all:
            break
        case .release:
            items = items.filter { $0.version.isNotPrerelease }
        case .prerelease:
            items = items.filter { $0.version.isPrerelease }
        }

        if !filters.architectureFilters.isEmpty {
            items = items.filter { filters.architectureFilters.matches($0.architectures) }
        }

        if let allowedMajorVersions = filters.allowedMajorVersions {
            items = items.filteringUninstalledVersions(allowedMajorVersions: allowedMajorVersions)
        }

        if !filters.searchText.isEmpty {
            items = items.filter { $0.version.appleDescription.contains(filters.searchText) }
        }

        if filters.installedOnly {
            items = items.filter { $0.installState.installed }
        }

        return items
    }

    func groupedByMajorVersion() -> [XcodeMajorVersionGroup] {
        Dictionary(grouping: self, by: { $0.version.major })
            .map { majorVersion, xcodes in
                let minorVersionGroups = Dictionary(grouping: xcodes, by: { $0.version.minor })
                    .map { minorVersion, minorXcodes in
                        XcodeMinorVersionGroup(
                            majorVersion: majorVersion,
                            minorVersion: minorVersion,
                            versions: minorXcodes.sorted { $0.version > $1.version }
                        )
                    }
                    .sorted { $0.minorVersion > $1.minorVersion }

                return XcodeMajorVersionGroup(
                    majorVersion: majorVersion,
                    minorVersionGroups: minorVersionGroups
                )
            }
            .sorted { $0.majorVersion > $1.majorVersion }
    }

    func filteringUninstalledVersions(allowedMajorVersions: Int) -> [XcodeListItem] {
        guard
            let latestMajor = sorted(by: { $0.version < $1.version })
                .filter({ $0.version.isNotPrerelease })
                .last?
                .version
                .major
        else { return self }

        let oldestAllowedMajor = latestMajor - Swift.min(latestMajor, allowedMajorVersions)
        return filter { item in
            if item.installState.notInstalled, item.version.major < oldestAllowedMajor {
                return false
            }
            return true
        }
    }

    var latestRelease: XcodeListItem? {
        filter { $0.version.isNotPrerelease }
            .sorted { $0.version < $1.version }
            .last
    }
}

private struct XcodeListFilteredElement<Element> {
    let element: Element
    let item: XcodeListItem
}

private extension Array {
    func applying(_ filters: XcodeListFilters) -> [Element] where Element: XcodeListFilterable {
        var elements = self

        switch filters.versionFilter {
        case .all:
            break
        case .release:
            elements = elements.filter { $0.listItem.version.isNotPrerelease }
        case .prerelease:
            elements = elements.filter { $0.listItem.version.isPrerelease }
        }

        if !filters.architectureFilters.isEmpty {
            elements = elements.filter { filters.architectureFilters.matches($0.listItem.architectures) }
        }

        if let allowedMajorVersions = filters.allowedMajorVersions {
            elements = elements.filteringUninstalledVersions(allowedMajorVersions: allowedMajorVersions)
        }

        if !filters.searchText.isEmpty {
            elements = elements.filter { $0.listItem.version.appleDescription.contains(filters.searchText) }
        }

        if filters.installedOnly {
            elements = elements.filter { $0.listItem.installState.installed }
        }

        return elements
    }

    func filteringUninstalledVersions(allowedMajorVersions: Int) -> [Element] where Element: XcodeListFilterable {
        guard
            let latestMajor = sorted(by: { $0.listItem.version < $1.listItem.version })
                .filter({ $0.listItem.version.isNotPrerelease })
                .last?
                .listItem
                .version
                .major
        else { return self }

        let oldestAllowedMajor = latestMajor - Swift.min(latestMajor, allowedMajorVersions)
        return filter { element in
            if element.listItem.installState.notInstalled, element.listItem.version.major < oldestAllowedMajor {
                return false
            }
            return true
        }
    }
}

private protocol XcodeListFilterable {
    var listItem: XcodeListItem { get }
}

extension XcodeListItem: XcodeListFilterable {
    fileprivate var listItem: XcodeListItem { self }
}

extension XcodeListFilteredElement: XcodeListFilterable {
    fileprivate var listItem: XcodeListItem { item }
}
