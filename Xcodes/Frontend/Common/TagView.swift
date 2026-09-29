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

        var color: Color {
            switch self {
            case .beta: return .orange
            case .releaseCandidate: return .purple
            case .otherPrerelease: return .teal
            case .latest: return .green
            }
        }
    }

    let label: Text
    let kind: Kind

    var body: some View {
        label
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kind.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(kind.color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(kind.color.opacity(0.35), lineWidth: 0.5))
            .fixedSize()
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

    static var latest: ReleaseTagView {
        ReleaseTagView(label: Text("Tag.Latest"), kind: .latest)
    }
}
