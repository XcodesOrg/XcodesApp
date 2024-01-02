import Foundation
import Path

public struct XcodesShell {
    public var installedRuntimes: () async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.bin.join("xcrun"), "simctl", "runtime", "list", "-j")
    }
    public var mountDmg: (URL) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.bin.join("hdiutil"), "attach", "-nobrowse", "-plist", $0.path)
    }
    public var unmountDmg: (URL) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.bin.join("hdiutil"), "detach", $0.path)
    }
    public var expandPkg: (URL, URL) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.sbin.join("pkgutil"), "--verbose", "--expand", $0.path, $1.path)
    }
    public var createPkg: (URL, URL) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.sbin.join("pkgutil"), "--flatten", $0.path, $1.path)
    }
    public var installPkg: (URL, String) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.sbin.join("installer"), "-pkg", $0.path, "-target", $1)
    }
    public var installRuntimeImage: (URL) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.bin.join("xcrun"), "simctl", "runtime", "add", $0.path)
    }
    public var deleteRuntime: (String) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.bin.join("xcrun"), "simctl", "runtime", "delete", $0)
    }
}
