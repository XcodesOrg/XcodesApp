//
//  CompilersView.swift
//  Xcodes
//
//  Created by Duong Thai on 13/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI
import struct XCModel.Compilers

struct CompilersView: View {
    let compilers: Compilers?

    var body: some View {
        if let compilers = compilers {
            VStack(alignment: .leading) {
                Text("Compilers").font(.headline)
                Text(Self.content(from: compilers))
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        } else {
            EmptyView()
        }
    }

    static func content(from compilers: Compilers) -> String {
        [ ("Swift", compilers.swift),
          ("Clang", compilers.clang),
          ("LLVM", compilers.llvm),
          ("LLVM GCC", compilers.llvm_gcc),
          ("GCC", compilers.gcc)
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
    }
}

#Preview {
  let compilers = Compilers(
    gcc: .init(number: "4"),
    llvm_gcc: .init(number: "213"),
    llvm: .init(number: "2.3"),
    clang: .init(number: "7.3"),
    swift: .init(number: "5.3.2")
  )

  return CompilersView(compilers: compilers)
    .padding()
}
