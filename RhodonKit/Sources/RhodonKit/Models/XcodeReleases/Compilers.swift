//
//  Compilers.swift
//  xcodereleases
//
//  Created by Xcode Releases on 4/4/18.
//  Copyright © 2018 Xcode Releases. All rights reserved.
//

import Foundation

public struct Compilers: Codable {
    public let gcc: [XcodeVersion]?
    public let llvmGcc: [XcodeVersion]?
    public let llvm: [XcodeVersion]?
    public let clang: [XcodeVersion]?
    public let swift: [XcodeVersion]?

    enum CodingKeys: String, CodingKey {
        case gcc
        case llvmGcc = "llvm_gcc"
        case llvm
        case clang
        case swift
    }

    public init(
        gcc: XcodeVersion? = nil,
        llvmGcc: XcodeVersion? = nil,
        llvm: XcodeVersion? = nil,
        clang: XcodeVersion? = nil,
        swift: XcodeVersion? = nil
    ) {
        self.gcc = gcc.map { [$0] }
        self.llvmGcc = llvmGcc.map { [$0] }
        self.llvm = llvm.map { [$0] }
        self.clang = clang.map { [$0] }
        self.swift = swift.map { [$0] }
    }

    public init(
        gcc: [XcodeVersion]?,
        llvmGcc: [XcodeVersion]?,
        llvm: [XcodeVersion]?,
        clang: [XcodeVersion]?,
        swift: [XcodeVersion]?
    ) {
        self.gcc = gcc?.isEmpty == true ? nil : gcc
        self.llvmGcc = llvmGcc?.isEmpty == true ? nil : llvmGcc
        self.llvm = llvm?.isEmpty == true ? nil : llvm
        self.clang = clang?.isEmpty == true ? nil : clang
        self.swift = swift?.isEmpty == true ? nil : swift
    }
}
