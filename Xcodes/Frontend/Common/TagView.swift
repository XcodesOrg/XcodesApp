//
//  TagView.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2025-06-25.//


import SwiftUI
import Version
import XcodesKit

struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(.quaternary)
            )
    }
}

/// A tinted capsule that classifies a release at a glance, e.g. Beta, RC or Latest.
struct ReleaseTagView: View {
    enum Kind {
        case beta
        case releaseCandidate
        case otherPrerelease
        case latest
        case active

        var color: Color {
            switch self {
            case .beta: return .orange
            case .releaseCandidate: return .purple
            case .otherPrerelease: return .teal
            case .latest: return .green
            case .active: return .blue
            }
        }
    }

    let label: Text
    let kind: Kind
    /// On a selected row the tint would disappear into the highlight, so draw it in white instead
    var isOnSelection = false

    var body: some View {
        let color = isOnSelection ? Color.white : kind.color
        label
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(isOnSelection ? 0.22 : 0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(isOnSelection ? 0.6 : 0.35), lineWidth: 0.5))
            .fixedSize()
    }

    func onSelection(_ isOnSelection: Bool) -> ReleaseTagView {
        var tag = self
        tag.isOnSelection = isOnSelection
        return tag
    }
}

extension ReleaseTagView {
    /// A tag describing a version's prerelease, e.g. "Beta 6" or "RC 2", or nil for a release.
    init?(prereleaseOf version: Version) {
        guard version.isPrerelease else { return nil }
        let base = Version(major: version.major, minor: version.minor, patch: version.patch).appleDescription
        let text = version.appleDescription
            .dropFirst(base.count)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "Release Candidate", with: "RC")
        self.init(label: Text(verbatim: text), kind: Self.kind(forPrerelease: version))
    }

    static func kind(forPrerelease version: Version) -> Kind {
        let identifiers = version.prereleaseIdentifiers.joined(separator: " ").lowercased()
        if identifiers.contains("beta") { return .beta }
        if identifiers.contains("release") || identifiers.contains("rc") || identifiers.contains("gm") { return .releaseCandidate }
        return .otherPrerelease
    }

    static var active: ReleaseTagView {
        ReleaseTagView(label: Text("Tag.Active"), kind: .active)
    }

    static var latest: ReleaseTagView {
        ReleaseTagView(label: Text("Tag.Latest"), kind: .latest)
    }
}
