//
//  Hashcash.swift
//  
//
//  Created by Matt Kiazyk on 2023-02-23.
//

import Foundation
import CryptoKit
import CommonCrypto

public struct Hashcash {

    public func mint(resource: String,
                     bits: UInt = 20,
                     ext: String = "",
                     saltCharacters: UInt = 16,
                     stampSeconds: Bool = true,
                     date: String? = nil) -> String? {
        
        let ver = "1"
        
        var ts: String
        if let date = date {
            ts = date
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = stampSeconds ? "yyMMddHHmmss" : "yyMMdd"
            ts = formatter.string(from: Date())
        }
        
        let challenge = "\(ver):\(bits):\(ts):\(resource):"
        
        var counter = 0
        let hexDigits = Int(ceil((Double(bits) / 4)))
        let zeros = String(repeating: "0", count: hexDigits)
        
        while true {
            guard let digest = ("\(challenge):\(counter)").sha1 else {
                print("ERROR: Can't generate SHA1 digest")
                return nil
            }
            
            if digest.prefix(hexDigits) == zeros {
                return "\(challenge):\(counter)"
            }
            counter += 1
        }
    }
    
    /**
     Checks whether a stamp is valid
     - parameter stamp: stamp to check e.g. 1:16:040922:foo::+ArSrtKd:164b3
     - parameter resource: resource to check against
     - parameter bits: minimum bit value to check
     - parameter expiration: number of seconds old the stamp may be
     - returns: true if stamp is valid
     */
    public func check(stamp: String,
                      resource: String? = nil,
                      bits: UInt,
                      expiration: UInt? = nil) -> Bool {
        
        guard let stamped = Stamp(stamp: stamp) else {
            print("Invalid stamp format")
            return false
        }
        
        if let res = resource, res != stamped.resource {
            print("Resources do not match")
            return false
        }
        
        var count = bits
        if let claim = stamped.claim {
            if bits > claim {
                return false
            } else {
                count = claim
            }
        }
        
        if let expiration = expiration {
            let goodUntilDate = Date(timeIntervalSinceNow: -TimeInterval(expiration))
            if (stamped.date < goodUntilDate) {
                print("Stamp expired")
                return false
            }
        }
        
        guard let digest = stamp.sha1 else {
            return false
        }
        
        let hexDigits = Int(ceil((Double(count) / 4)))
        return digest.hasPrefix(String(repeating: "0", count: hexDigits))
    }
    
    /**
     Generates random string of chosen length
     - parameter length:    length of random string
     - returns: random string
     */
    internal func salt(length: UInt) -> String {
        let allowedCharacters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+/="
        var result = ""
        
        for _ in 0..<length {
            let randomValue = arc4random_uniform(UInt32(allowedCharacters.count))
            result += "\(allowedCharacters[allowedCharacters.index(allowedCharacters.startIndex, offsetBy: Int(randomValue))])"
        }
        return result
    }
}

extension String {
    var sha1: String? {
        let data = Data(self.utf8)
        var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02x", $0) }
        return hexBytes.joined()
    }
}

