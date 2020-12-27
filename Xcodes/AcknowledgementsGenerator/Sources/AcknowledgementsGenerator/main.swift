//
//  main.swift
//  spm-licenses
//
//  Created by Sergii Kryvoblotskyi on 11/11/19.
//  Copyright © 2019 MacPaw. All rights reserved.
//

import Foundation
import AppKit

let arguments = CommandLine.arguments
guard let projectIndex = arguments.firstIndex(of: "-p"), let projectPath = arguments[safe: projectIndex + 1] else {
    print("Project path is missing. Specify -p.")
    exit(EXIT_FAILURE)
}

guard let outputIndex = arguments.firstIndex(of: "-o"), let outputPath = arguments[safe: outputIndex + 1] else {
    print("Output path is missing. Specify -o.")
    exit(EXIT_FAILURE)
}

let fileManager = FileManager.default

let projectURL = URL(fileURLWithPath: projectPath.expandingTildeInPath)
if !fileManager.fileExists(atPath: projectURL.path) {
    print("xcodeproj not found at \(projectURL)")
    exit(EXIT_FAILURE)
}

let packageURL = projectURL.appendingPathComponent("project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
if !fileManager.fileExists(atPath: packageURL.path) {
    print("Package.resolved not found at \(packageURL)")
    exit(EXIT_FAILURE)
}

let packageData = try Data(contentsOf: packageURL)
let packageInfo = try JSONSerialization.jsonObject(with: packageData, options: .allowFragments)

guard let package = packageInfo as? [String: Any] else {
    print("Invalid package format")
    exit(EXIT_FAILURE)
}

guard let object = package["object"] as? [String: Any] else {
    print("Invalid obejct format")
    exit(EXIT_FAILURE)
}

guard let pins = object["pins"] as? [[String: Any]] else {
    print("Invalid pins format")
    exit(EXIT_FAILURE)
}

let projectsURL = Xcode.derivedDataURL
func projectsInfo(at url: URL) throws -> [Xcode.Project] {
    try fileManager
        .contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        .map { $0.appendingPathComponent("info.plist") }
        .compactMap {
            guard let info = NSDictionary(contentsOf: $0) as? [String: Any] else { return nil }
            return Xcode.Project(url: $0, info: info)
    }
}
let projects = try projectsInfo(at: projectsURL)

// Despite the naming, if the project only has an xcodeproj and not an xcworkspace, the WorkspacePath value will be the path to the xcodeproj
guard let currentProject = projects.first(where: ({ $0.workspacePath == projectPath.expandingTildeInPath })) else {
    print("Derived data missing for project")
    exit(EXIT_FAILURE)
}

let checkouts = currentProject.url.deletingLastPathComponent().appendingPathComponent("SourcePackages/checkouts")
let checkedDependencies = try fileManager.contentsOfDirectory(at: checkouts, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

let spmLicences: [Xcode.Project.License] = checkedDependencies.compactMap {
    let supportedFilenames = ["LICENSE", "LICENSE.txt", "LICENSE.md"]
    for filename in supportedFilenames {
        let licenseURL = $0.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: licenseURL.path) {
            return Xcode.Project.License(url: licenseURL, name: $0.lastPathComponent)
        }
    }
    return nil
}

var manualLicenses: [Xcode.Project.License] = []
let enumerator = fileManager.enumerator(at: projectURL.deletingLastPathComponent(), includingPropertiesForKeys: [URLResourceKey.nameKey], options: .skipsHiddenFiles)!
for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".LICENSE") {
    manualLicenses.append(
        Xcode.Project.License(
            url: url, 
            name: url.lastPathComponent.replacingOccurrences(of: ".LICENSE", with: "")
        )
    )
}

let licences = spmLicences + manualLicenses

let acknowledgementsAttributedString = NSMutableAttributedString()
for licence in licences {
    acknowledgementsAttributedString.append(NSAttributedString(string: licence.name + "\n\n", attributes: [.font: NSFont.preferredFont(forTextStyle: .title2)]))
    let licenseContents = try String(contentsOf: licence.url)
    acknowledgementsAttributedString.append(NSAttributedString(string: licenseContents + "\n\n", attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]))
}

guard let data = acknowledgementsAttributedString.rtf(from: NSRange(location: 0, length: acknowledgementsAttributedString.length), documentAttributes: [:]) else {
    print("Failed to create RTF data")
    exit(EXIT_FAILURE)
}
try data.write(to: URL(fileURLWithPath: outputPath.expandingTildeInPath))

print("Licenses have been saved to \(outputPath)")
