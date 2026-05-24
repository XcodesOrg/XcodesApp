import Foundation

public struct HostHardware: Sendable {
    public init() {}

    /// Determines the architecture of the Mac on which we're running.
    public static func currentMachineHardwareName() -> String? {
        var sysInfo = utsname()
        let result = uname(&sysInfo)

        guard result == EXIT_SUCCESS else {
            return nil
        }

        let bytes = Data(bytes: &sysInfo.machine, count: Int(_SYS_NAMELEN))
        return String(data: bytes, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }

    public static func isAppleSilicon(machineHardwareName: String? = currentMachineHardwareName()) -> Bool {
        machineHardwareName == Architecture.arm64.rawValue
    }
}
