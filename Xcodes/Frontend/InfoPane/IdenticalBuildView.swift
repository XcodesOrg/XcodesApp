//
//  IdenticalBuildView.swift
//  Xcodes
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
                    Text("IdenticalBuilds")
                    Image(systemName: "square.fill.on.square.fill")
                        .foregroundColor(.secondary)
                        .accessibility(hidden: true)
                        .help("IdenticalBuilds.help")
                }
                .font(.headline)

                ForEach(builds, id: \.description) { version in
                    Text("• \(version.appleDescription)")
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement()
            .accessibility(label: Text("IdenticalBuilds"))
            .accessibility(value: Text(accessibilityDescription))
            .accessibility(hint: Text("IdenticalBuilds.help"))
        }
    }

    init(builds: [Version]) {
        self.builds = builds
        self.isEmpty = builds.isEmpty
        self.accessibilityDescription = builds
            .map(\.appleDescription)
            .joined(separator: ", ")
    }
}

struct IdenticalBuildsView_Preview: PreviewProvider {
    static var previews: some View {
        WrapperView()
    }
}

private struct WrapperView: View {
    @State var isEmpty = false
    var builds: [Version] {
        isEmpty
        ? []
        : [.init(xcodeVersion: "15.0")!,
           .init(xcodeVersion: "15.1")!]
    }

    var body: some View {
        VStack {
            HStack {
                IdenticalBuildsView(builds: builds)
                .border(.red)
            }
            Spacer()
            Toggle(isOn: $isEmpty) {
                Text("Is Empty?")
            }
        }
        .animation(.default)
        .frame(width: 300, height: 100)
        .padding()
    }
}
