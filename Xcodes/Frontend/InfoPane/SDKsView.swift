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
    let sdks: SDKs?

    var body: some View {
        if let sdks = sdks {
            VStack(alignment: .leading) {
                Text("SDKs").font(.headline)
                Text(Self.content(from: sdks)).font(.subheadline)
            }
        } else {
            EmptyView()
        }
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

        return content
    }
}

struct SDKsView_Preview: PreviewProvider {
    static var previews: some View {
        WrapperView()
    }
}

private struct WrapperView: View {
    @State var isNil = false
    var sdks: SDKs? {
        isNil
        ? nil
        : SDKs(macOS: .init(number: "11.1"),
               iOS: .init(number: "14.3"),
               watchOS: .init(number: "7.3"),
               tvOS: .init(number: "14.3"))
    }

    var body: some View {
        VStack {
            HStack {
                SDKsView(sdks: sdks)
                    .border(.red)
            }
            Spacer()
            Toggle(isOn: $isNil) {
                Text("Is Nil?")
            }
        }
        .animation(.default)
        .frame(width: 200, height: 100)
        .padding()
    }
}
