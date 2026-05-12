import Foundation


struct Hardware {
    
    ///
    ///  Determines the architecture of the Mac on which we're running. Returns `arm64` for Apple Silicon
    ///  and `x86_64` for Intel-based Macs or `nil` if the system call fails.
    static func getMachineHardwareName() -> String?
    {
        var sysInfo = utsname()
        let retVal = uname(&sysInfo)
        var finalString: String? = nil
        
        if retVal == EXIT_SUCCESS
        {
            let bytes = Data(bytes: &sysInfo.machine, count: Int(_SYS_NAMELEN))
            finalString = String(data: bytes, encoding: .utf8)
        }
        
        // _SYS_NAMELEN will include a billion null-terminators. Clear those out so string comparisons work as you expect.
        return finalString?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }
    
    static func isAppleSilicon() -> Bool {
        return Hardware.getMachineHardwareName() == "arm64"
    }
}
