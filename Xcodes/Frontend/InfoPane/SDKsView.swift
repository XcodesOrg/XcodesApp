//
//  SDKsView.swift
//  Xcodes
//
//  Created by Duong Thai on 13/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI
import struct XCModel.SDKs

struct SDKsView: View {
    let content: String

    var body: some View {
        if content.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading) {
                Text("SDKs").font(.headline)
                Text(content)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
    }

    init(sdks: SDKs?) {
        guard let sdks = sdks else {
            self.content = ""
            return
        }
        let content = Self.content(from: sdks)
        self.content = content
    }

    static private func content(from sdks: SDKs) -> String {
        let content: String = [
            ("macOS", sdks.macOS),
            ("iOS", sdks.iOS),
            ("watchOS", sdks.watchOS),
            ("tvOS", sdks.tvOS)
        ].compactMap {             // remove nil compiler
            guard $0.1 != nil,     // has version array
                  !$0.1!.isEmpty   // has at least 1 version
            else { return nil }

            let numbers = $0.1!.compactMap { $0.number } // remove nil number
            guard !numbers.isEmpty // has at least 1 number
            else { return nil }

            // description for each type of compilers
            return "\($0.0): \(numbers.joined(separator: ", "))"
        }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespaces)

        return content
    }
}

#Preview {
  let sdks = SDKs(
    macOS: .init(number: "11.1"),
    iOS: .init(number: "14.3"),
    watchOS: .init(number: "7.3"),
    tvOS: .init(number: "14.3"))

  return SDKsView(sdks: sdks)
    .padding()
}
