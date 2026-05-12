//
//  Hashcash.swift
//  
//
//  Created by Matt Kiazyk on 2023-02-23.
//

import Foundation
import CryptoKit
import CommonCrypto

/*
# This App Store Connect hashcash spec was generously donated by...
 #
 #                         __  _
 #    __ _  _ __   _ __   / _|(_)  __ _  _   _  _ __  ___  ___
 #   / _` || '_ \ | '_ \ | |_ | | / _` || | | || '__|/ _ \/ __|
 #  | (_| || |_) || |_) ||  _|| || (_| || |_| || |  |  __/\__ \
 #   \__,_|| .__/ | .__/ |_|  |_| \__, | \__,_||_|   \___||___/
 #         |_|    |_|             |___/
 #
 #
*/
public struct Hashcash {
    /// A function to returned a minted hash, using a bit and resource string
    ///
    /**
      X-APPLE-HC: 1:11:20230223170600:4d74fb15eb23f465f1f6fcbf534e5877::6373
                  ^  ^      ^                       ^                     ^
                  |  |      |                       |                     +-- Counter
                  |  |      |                       +-- Resource
                  |  |      +-- Date YYMMDD[hhmm[ss]]
                  |  +-- Bits (number of leading zeros)
                  +-- Version
     
     We can't use an off-the-shelf Hashcash because Apple's implementation is not quite the same as the spec/convention.
     1. The spec calls for a nonce called "Rand" to be inserted between the Ext and Counter. They don't do that at all.
     2. The Counter conventionally encoded as base-64 but Apple just uses the decimal number's string representation.
      
     Iterate from Counter=0 to Counter=N finding an N that makes the SHA1(X-APPLE-HC) lead with Bits leading zero bits
     We get the "Resource" from the X-Apple-HC-Challenge header and Bits from X-Apple-HC-Bits
     */
    /// - Parameters:
    ///    - resource: a string to be used for minting
    ///    - bits: grabbed from `X-Apple-HC-Bits` header
    ///    - date: Default uses Date() otherwise used for testing to check.
    /// - Returns: A String hash to use in `X-Apple-HC` header on /signin
    public func mint(resource: String,
                     bits: UInt = 10,
                     date: String? = nil) -> String? {
        
        let ver = "1"
        
        var ts: String
        if let date = date {
            ts = date
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyMMddHHmmss"
            ts = formatter.string(from: Date())
        }
        
        let challenge = "\(ver):\(bits):\(ts):\(resource):"
        
        var counter = 0
        
        while true {
            guard let digest = ("\(challenge):\(counter)").sha1 else {
                print("ERROR: Can't generate SHA1 digest")
                return nil
            }
            
            if digest == bits {
                return "\(challenge):\(counter)"
            }
            counter += 1
        }
    }
}

extension String {
    var sha1: Int? {
        
        let data = Data(self.utf8)
        var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let bigEndianValue = digest.withUnsafeBufferPointer {
                 ($0.baseAddress!.withMemoryRebound(to: UInt32.self, capacity: 1) { $0 })
        }.pointee
        let value = UInt32(bigEndian: bigEndianValue)
        return value.leadingZeroBitCount
    }
}

