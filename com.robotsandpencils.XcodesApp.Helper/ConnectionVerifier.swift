// From https://github.com/securing/SimpleXPCApp/
// MIT License
// 
// Copyright (c) 2020 securing
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

class ConnectionVerifier {
    
    private static func prepareCodeReferencesFromAuditToken(connection: NSXPCConnection, secCodeOptional: inout SecCode?, secStaticCodeOptional: inout SecStaticCode?) -> Bool {
        let auditTokenData = AuditTokenHack.getAuditTokenData(from: connection)
        
        let attributesDictrionary = [
            kSecGuestAttributeAudit : auditTokenData
        ]
        
        if SecCodeCopyGuestWithAttributes(nil, attributesDictrionary as CFDictionary, SecCSFlags(rawValue: 0), &secCodeOptional) != errSecSuccess {
            NSLog("Couldn't get SecCode with the audit token")
            return false
        }
        
        guard let secCode = secCodeOptional else {
            NSLog("Couldn't unwrap the secCode")
            return false
        }
        
        SecCodeCopyStaticCode(secCode, SecCSFlags(rawValue: 0), &secStaticCodeOptional)
        
        guard let _ = secStaticCodeOptional else {
            NSLog("Couldn't unwrap the secStaticCode")
            return false
        }
        
        return true
    }
    
    private static func verifyHardenedRuntimeAndProblematicEntitlements(secStaticCode: SecStaticCode) -> Bool {
        var signingInformationOptional: CFDictionary? = nil
        if SecCodeCopySigningInformation(secStaticCode, SecCSFlags(rawValue: kSecCSDynamicInformation), &signingInformationOptional) != errSecSuccess {
            NSLog("Couldn't obtain signing information")
            return false
        }
        
        guard let signingInformation = signingInformationOptional else {
            return false
        }

        let signingInformationDict = signingInformation as NSDictionary
        
        let signingFlagsOptional = signingInformationDict.object(forKey: "flags") as? UInt32
        
        if let signingFlags = signingFlagsOptional {
            let hardenedRuntimeFlag: UInt32 = 0x10000
            if (signingFlags & hardenedRuntimeFlag) != hardenedRuntimeFlag {
                NSLog("Hardened runtime is not set for the sender")
                return false
            }
        } else {
            return false
        }
        
        let entitlementsOptional = signingInformationDict.object(forKey: "entitlements-dict") as? NSDictionary
        guard let entitlements = entitlementsOptional else {
            return false
        }
        NSLog("Entitlements are \(entitlements)")
        let problematicEntitlements = [
            "com.apple.security.get-task-allow",
            "com.apple.security.cs.disable-library-validation",
            "com.apple.security.cs.allow-dyld-environment-variables"
        ]

        // Skip this check for debug builds because they'll have the get-task-allow entitlement        
        #if !DEBUG
        for problematicEntitlement in problematicEntitlements {
            if let presentEntitlement = entitlements.object(forKey: problematicEntitlement) {
                if presentEntitlement as! Int == 1 {
                    NSLog("The sender has \(problematicEntitlement) entitlement set to true")
                    return false
                }
            }
        }
        #endif

        return true
    }
    
    private static func verifyWithRequirementString(secCode: SecCode) -> Bool {
        // Code Signing Requirement Language
        // https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html#//apple_ref/doc/uid/TP40005929-CH5-SW1
        let requirementString = "identifier \"\(clientBundleID)\" and info [CFBundleShortVersionString] >= \"1.0.0\" and anchor apple generic and certificate leaf[subject.OU] = \"\(subjectOrganizationalUnit)\"" as NSString
         
        var secRequirement: SecRequirement? = nil
        if SecRequirementCreateWithString(requirementString as CFString, SecCSFlags(rawValue: 0), &secRequirement) != errSecSuccess {
            NSLog("Couldn't create the requirement string")
            return false
        }
         
        if SecCodeCheckValidity(secCode, SecCSFlags(rawValue: 0), secRequirement) != errSecSuccess {
            NSLog("NSXPC client does not meet the requirements")
            return false
        }
        
        return true
    }
    
    public static func isValid(connection: NSXPCConnection) -> Bool {
        var secCodeOptional: SecCode? = nil
        var secStaticCodeOptional: SecStaticCode? = nil
        
        if !prepareCodeReferencesFromAuditToken(connection: connection, secCodeOptional: &secCodeOptional, secStaticCodeOptional: &secStaticCodeOptional) {
            return false
        }
        
        if !verifyHardenedRuntimeAndProblematicEntitlements(secStaticCode: secStaticCodeOptional!) {
            return false
        }
        
        if !verifyWithRequirementString(secCode: secCodeOptional!) {
            return false
        }
        
        return true
    }
    
}
