//
//  IdenticalBuildView.swift
//  Rhodon
//
//  Created by Duong Thai on 11/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI
import Version

struct IdenticalBuildsView: View {
    let builds: [Version]
    private let isEmpty: Bool
    private let accessibilityDescription: String

    var body: some View {
        if isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading) {
                HStack {
                    Text("Identical Builds")
                    Image(systemName: "square.fill.on.square.fill")
                        .foregroundColor(.secondary)
                        .accessibility(hidden: true)
                        .help(
                            // swiftlint:disable:next line_length
                            "Sometimes a prerelease and release version are the exact same build. Rhodon will automatically display these versions together."
                        )
                }
                .font(.headline)

                ForEach(builds, id: \.description) { version in
                    Text(verbatim: "• \(version.appleDescription)")
                        .font(.subheadline)
                }
            }
            .rhodonBackground()
            .accessibilityElement()
            .accessibility(label: Text("IdenticalBuilds"))
            .accessibility(value: Text(accessibilityDescription))
            .accessibility(hint: Text("IdenticalBuilds.help"))
        }
    }

    init(builds: [Version]) {
        self.builds = builds
        isEmpty = builds.isEmpty
        accessibilityDescription = builds
            .map(\.appleDescription)
            .joined(separator: ", ")
    }
}

let builds: [Version] = [.init(xcodeVersion: "15.0")!, .init(xcodeVersion: "15.1")!]

#Preview("Has Some Builds") {
    IdenticalBuildsView(builds: builds)
        .padding()
}

#Preview("No Build") {
    IdenticalBuildsView(builds: [])
        .padding()
}
