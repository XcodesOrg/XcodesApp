//
//  Xcode.swift
//  spm-licenses
//
//  Created by Sergii Kryvoblotskyi on 11/11/19.
//  Copyright © 2019 MacPaw. All rights reserved.
//

import Foundation

struct Xcode {
    
    static var derivedDataURL: URL {
        if let overridenPath = readOverridenDerivedDataPath() {
            return URL(fileURLWithPath: overridenPath.expandingTildeInPath)
        }
        let defaultPath = "~/Library/Developer/Xcode/DerivedData/".expandingTildeInPath
        return URL(fileURLWithPath: defaultPath)
    }
}

//defaults read com.apple.dt.Xcode.plist IDECustomDerivedDataLocation
//If the line returns
//
//The domain/default pair of (com.apple.dt.Xcode.plist, IDECustomDerivedDataLocation) does not exist
//it's the default path ~/Library/Developer/Xcode/DerivedData/ otherwise the custom path.
private extension Xcode {
    
    static func readOverridenDerivedDataPath() -> String? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read","com.apple.dt.Xcode.plist", "IDECustomDerivedDataLocation"]
        task.standardOutput = pipe
        try? task.run()
        let handle = pipe.fileHandleForReading
        let data = handle.readDataToEndOfFile()
        let path = String(data: data, encoding: String.Encoding.utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty ?? true) ? nil : path
    }
}

extension Xcode {
    
    struct Project {
        let url: URL
        let info: [String: Any]
        var workspacePath: String? {
            return info["WorkspacePath"] as? String
        }
    }
}

extension Xcode.Project {
    
    struct License {
        
        let url: URL
        let name: String
    }
}

extension Xcode.Project.License {
    
    func makeRepresentation() throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? ""
        return [
            "Title": name,
            "Type": "PSGroupSpecifier",
            "FooterText": text
        ]
    }
}
