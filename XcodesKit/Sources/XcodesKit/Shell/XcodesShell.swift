import Foundation
import Path

public struct XcodesShell: Sendable {
    public var installedRuntimes: @Sendable () async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.bin.join("xcrun"), "simctl", "runtime", "list", "-j")
    }
    public var mountDmg: @Sendable (URL) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.bin.join("hdiutil"), "attach", "-nobrowse", "-plist", $0.path)
    }
    public var unmountDmg: @Sendable (URL) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.bin.join("hdiutil"), "detach", $0.path)
    }
    public var expandPkg: @Sendable (URL, URL) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.sbin.join("pkgutil"), "--verbose", "--expand", $0.path, $1.path)
    }
    public var createPkg: @Sendable (URL, URL) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.sbin.join("pkgutil"), "--flatten", $0.path, $1.path)
    }
    public var installPkg: @Sendable (URL, String) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.sbin.join("installer"), "-pkg", $0.path, "-target", $1)
    }
    public var installRuntimeImage: @Sendable (URL) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.bin.join("xcrun"), "simctl", "runtime", "add", $0.path)
    }
    public var deleteRuntime: @Sendable (String) async throws -> ProcessOutput = {
        try await Process.run(Path.root.usr.bin.join("xcrun"), "simctl", "runtime", "delete", $0)
    }
   
    public var archs: @Sendable (URL) throws -> ProcessOutput = {
        try Process.run(Path.root.usr.bin.join("lipo"), "-archs", $0.path)
    }
}
