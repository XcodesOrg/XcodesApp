//
//  Compiler.swift
//  xcodereleases
//
//  Created by Xcode Releases on 4/4/18.
//  Copyright © 2018 Xcode Releases. All rights reserved.
//

import Foundation

public struct Compilers: Codable {
    public let gcc: Array<XcodeVersion>?
    public let llvm_gcc: Array<XcodeVersion>?
    public let llvm: Array<XcodeVersion>?
    public let clang: Array<XcodeVersion>?
    public let swift: Array<XcodeVersion>?
    
    public init(gcc: XcodeVersion? = nil, llvm_gcc: XcodeVersion? = nil, llvm: XcodeVersion? = nil, clang: XcodeVersion? = nil, swift: XcodeVersion? = nil) {
        self.gcc = gcc.map { [$0] }
        self.llvm_gcc = llvm_gcc.map { [$0] }
        self.llvm = llvm.map { [$0] }
        self.clang = clang.map { [$0] }
        self.swift = swift.map { [$0] }
    }
    
    public init(gcc: Array<XcodeVersion>?, llvm_gcc: Array<XcodeVersion>?, llvm: Array<XcodeVersion>?, clang: Array<XcodeVersion>?, swift: Array<XcodeVersion>?) {
        self.gcc = gcc?.isEmpty == true ? nil : gcc
        self.llvm_gcc = llvm_gcc?.isEmpty == true ? nil : llvm_gcc
        self.llvm = llvm?.isEmpty == true ? nil : llvm
        self.clang = clang?.isEmpty == true ? nil : clang
        self.swift = swift?.isEmpty == true ? nil : swift
    }
}
