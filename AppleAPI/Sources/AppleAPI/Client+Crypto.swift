import CommonCrypto
import Foundation

extension Client {
    func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    func pbkdf2(_ input: PBKDF2Input) -> Data? {
        guard let passwordData = input.password.data(using: .utf8) else { return nil }
        let hashedPasswordDataRaw = sha256(data: passwordData)
        let hashedPasswordData = switch input.srpProtocol {
        case .s2k: hashedPasswordDataRaw
        // the legacy s2k_fo protocol requires hex-encoding the digest before performing PBKDF2.
        case .s2kFo: Data(hashedPasswordDataRaw.hexEncodedString().lowercased().utf8)
        }

        var derivedKeyData = Data(repeating: 0, count: input.keyByteCount)
        let derivedCount = derivedKeyData.count
        let derivationStatus: Int32 = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            guard let keyBuffer = derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return Int32(kCCParamError)
            }
            return input.saltData.withUnsafeBytes { saltBytes -> Int32 in
                guard let saltBuffer = saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return Int32(kCCParamError)
                }
                return hashedPasswordData.withUnsafeBytes { hashedPasswordBytes -> Int32 in
                    guard let passwordBuffer = hashedPasswordBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    else { return Int32(kCCParamError) }
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer,
                        hashedPasswordData.count,
                        saltBuffer,
                        input.saltData.count,
                        input.prf,
                        UInt32(input.rounds),
                        keyBuffer,
                        derivedCount
                    )
                }
            }
        }
        return derivationStatus == kCCSuccess ? derivedKeyData : nil
    }
}
