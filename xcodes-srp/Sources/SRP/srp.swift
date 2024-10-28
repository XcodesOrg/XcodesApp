//
//  Implementation.swift
//  swift-srp
//
//  Created by Matt Kiazyk on 2024-10-24.
//


import Foundation
import BigInt
import Crypto

/// Creates the salted verification key based on a user's username and
/// password. Only the salt and verification key need to be stored on the
/// server, there's no need to keep the plain-text password. 
///
/// Keep the verification key private, as it can be used to brute-force 
/// the password from.
///
/// - Parameters:
///   - using: hash function to use
///   - username: user's username
///   - password: user's password
///   - salt: (optional) custom salt value; if providing a salt, make sure to
///       provide a good random salt of at least 16 bytes. Default is to
///       generate a salt of 16 bytes.
///   - group: `Group` parameters; default is 2048-bits group.
///   - algorithm: which `Digest.Algorithm` to use; default is SHA1.
/// - Returns: salt (s) and verification key (v)
public func createSaltedVerificationKey<H: HashFunction>(
    using hashFunction: H.Type,
    group: Group = .N2048,
    username: String,
    password: String,
    salt: Data? = nil)
    -> (salt: Data, verificationKey: Data)
{
    let salt = salt ?? randomBytes(16)
    let x = Implementation<H>.calculate_x(salt: salt, username: username, password: password)
    return createSaltedVerificationKey(from: x, salt: salt, group: group)
}

/// Creates the salted verification key based on a precomputed SRP x value.
/// Only the salt and verification key need to be stored on the
/// server, there's no need to keep the plain-text password.
///
/// Keep the verification key private, as it can be used to brute-force
/// the password from.
///
/// - Parameters:
///   - x: precomputed SRP x
///   - salt: (optional) custom salt value; if providing a salt, make sure to
///       provide a good random salt of at least 16 bytes. Default is to
///       generate a salt of 16 bytes.
///   - group: `Group` parameters; default is 2048-bits group.
/// - Returns: salt (s) and verification key (v)
public func createSaltedVerificationKey(
    from x: Data,
    salt: Data? = nil,
    group: Group = .N2048)
    -> (salt: Data, verificationKey: Data)
{
    return createSaltedVerificationKey(from: BigUInt(x), salt: salt, group: group)
}

func createSaltedVerificationKey(
    from x: BigUInt,
    salt: Data? = nil,
    group: Group = .N2048)
    -> (salt: Data, verificationKey: Data)
{
    let salt = salt ?? randomBytes(16)
    let v = calculate_v(group: group, x: x)
    return (salt, v.serialize())
}

func pad(_ data: Data, to size: Int) -> Data {
    precondition(size >= data.count, "Negative padding not possible")
    return Data(count: size - data.count) + data
}

enum Implementation<HF: HashFunction> {
    // swiftlint:disable:next identifier_name
    static func H(_ data: Data) -> Data {
        return Data(HF.hash(data: data))
    }

    //u = H(PAD(A) | PAD(B))
    static func calculate_u(group: Group, A: Data, B: Data) -> BigUInt {
        let size = group.N.serialize().count
        return BigUInt(H(pad(A, to: size) + pad(B, to: size)))
    }

    //M1 = H(H(N) XOR H(g) | H(I) | s | A | B | K)
    static func calculate_M(group: Group, username: String, salt: Data, A: Data, B: Data, K: Data) -> Data {
        let serializedN = group.N.serialize()
        let sizeN = serializedN.count
        let HN_xor_Hg = (H(serializedN) ^ H(pad(group.g.serialize(), to: sizeN)))!
        let HI = H(username.data(using: .utf8)!)
        return H(HN_xor_Hg + HI + salt + A + B + K)
    }

    //HAMK = H(A | M | K)
    static func calculate_HAMK(A: Data, M: Data, K: Data) -> Data {
        return H(A + M + K)
    }

    //k = H(N | PAD(g))
    static func calculate_k(group: Group) -> BigUInt {
        let size = group.N.serialize().count
        return BigUInt(H(group.N.serialize() + pad(group.g.serialize(), to: size)))
    }

    //x = H(s | H(I | ":" | P))
    static func calculate_x(salt: Data, username: String, password: String) -> BigUInt {
        if username.count > 0 {
            return BigUInt(H(salt + H("\(username):\(password)".data(using: .utf8)!)))
        }

        let passwordData = Data(base64Encoded: password.data(using: .utf8)!)!
        return BigUInt(H(salt + H(Data([0x3A]) + passwordData)))
    }
}

// v = g^x % N
func calculate_v(group: Group, x: BigUInt) -> BigUInt {
    return group.g.power(x, modulus: group.N)
}

func randomBytes(_ count: Int) -> Data {
    return Data((0..<count).map { _ in UInt8.random(in: 0...255) })
}
