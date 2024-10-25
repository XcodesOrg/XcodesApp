
import Foundation
import BigInt
import Crypto

/// SRP Client; the party that initializes the authentication and
/// must proof possession of the correct password.
public class SRPClient<H: HashFunction> {
    let a: BigUInt
    let A: BigUInt

    let group: Group
    typealias impl = Implementation<H> // swiftlint:disable:this type_name

    let username: String
    var password: String?
    var precomputedX: BigUInt?

    public var HAMK: Data?
    var K: Data?

    /// Whether the session is authenticated, i.e. the password
    /// was verified by the server and proof of a valid session
    /// key was provided by the server. If `true`, `sessionKey`
    /// is also available.
    public private(set) var isAuthenticated = false

    private init(
        username: String,
        group: Group = .N2048,
        privateKey: Data? = nil)
    {
        self.username = username
        self.group = group
        if let privateKey = privateKey {
            a = BigUInt(privateKey)
        } else {
            a = BigUInt(Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
        }
        // A = g^a % N
        A = group.g.power(a, modulus: group.N)
    }

    /// Initialize the Client SRP party with a password.
    ///
    /// - Parameters:
    ///   - username: user's username.
    ///   - password: user's password.
    ///   - group: which `Group` to use, must be the same for the
    ///       server as well as the pre-stored verificationKey.
    ///   - privateKey: (optional) custom private key (a); if providing
    ///       the private key of the `Client`, make sure to provide a
    ///       good random key of at least 32 bytes. Default is to
    ///       generate a private key of 128 bytes. You MUST not re-use
    ///       the private key between sessions.
    public convenience init(
        username: String,
        password: String,
        group: Group = .N2048,
        privateKey: Data? = nil)
    {
        self.init(username: username, group: group, privateKey: privateKey)
        self.password = password
    }

    /// Initialize the Client SRP party with a precomputed x.
    ///
    /// - Parameters:
    ///   - username: user's username.
    ///   - precomputedX: precomputed SRP x.
    ///   - group: which `Group` to use, must be the same for the
    ///       server as well as the pre-stored verificationKey.
    ///   - privateKey: (optional) custom private key (a); if providing
    ///       the private key of the `Client`, make sure to provide a
    ///       good random key of at least 32 bytes. Default is to
    ///       generate a private key of 128 bytes. You MUST not re-use
    ///       the private key between sessions.
    public convenience init(
        username: String,
        precomputedX: Data,
        group: Group = .N2048,
        privateKey: Data? = nil)
    {
        self.init(username: username, group: group, privateKey: privateKey)
        self.precomputedX = BigUInt(precomputedX)
    }

    /// Starts authentication. This method is a no-op.
    ///
    /// - Returns: `publicKey` (A)
    public func startAuthentication() -> Data {
        return publicKey
    }

    /// Process the challenge provided by the server. This sets the `sessionKey`
    /// and generates proof that it generated the correct key from the password
    /// and the challenge. After the server has also proven the validity of their
    /// key, the `sessionKey` can be used.
    ///
    /// - Parameters:
    ///   - salt: user-specific salt (s)
    ///   - publicKey: server's public key (B)
    /// - Returns: key proof (M)
    /// - Throws: `AuthenticationFailure.invalidPublicKey` if the server's
    ///     public key is invalid (i.e. B % N is zero).
    public func processChallenge(salt: Data, publicKey serverPublicKey: Data, isEncryptedPassword: Bool, encryptedPassword: String? = nil) throws -> Data {
        let H = impl.H
        let N = group.N

        let B = BigUInt(serverPublicKey)

        guard B % N != 0 else {
            throw AuthenticationFailure.invalidPublicKey
        }

        let u = impl.calculate_u(group: group, A: publicKey, B: serverPublicKey)
        let k = impl.calculate_k(group: group)
        
        let x = self.precomputedX ?? (isEncryptedPassword ? impl.calculate_x(salt: salt, username: "", password: encryptedPassword!) : impl.calculate_x(salt: salt, username: username, password: password!))
        let v = calculate_v(group: group, x: x)

        // shared secret
        // S = (B - kg^x) ^ (a + ux)
        // Note that v = g^x, and that B - kg^x might become negative, which
        // cannot be stored in BigUInt. So we'll add N to B_ and make sure kv
        // isn't greater than N.
        let S = (B + N - k * v % N).power(a + u * x, modulus: N)

        // session key
        K = H(S.serialize())

        // client verification
        let M = impl.calculate_M(group: group, username: username, salt: salt, A: publicKey, B: serverPublicKey, K: K!)

        // server verification
        HAMK = impl.calculate_HAMK(A: publicKey, M: M, K: K!)
        return M
    }

    /// After the server has verified that the password is correct,
    /// it will send proof of the derived session key. This is verified
    /// on our end and finalizes the authentication session. After this
    /// step, the `sessionKey` is available.
    ///
    /// - Parameter HAMK: proof of the server that it derived the same
    ///     session key.
    /// - Throws:
    ///    - `AuthenticationFailure.missingChallenge` if this method
    ///      is called before calling `processChallenge`.
    ///    - `AuthenticationFailure.keyProofMismatch` if the proof
    ///      doesn't match our own.
    public func verifySession(keyProof serverKeyProof: Data) throws {
        guard let HAMK = HAMK else {
            throw AuthenticationFailure.missingChallenge
        }
        guard HAMK == serverKeyProof else {
            throw AuthenticationFailure.keyProofMismatch
        }
        isAuthenticated = true
    }

    /// The client's public key (A). For every authentication
    /// session a new public key is generated.
    public var publicKey: Data {
        return A.serialize()
    }

    /// The client's private key (a). For every authentication
    /// session a new random private key is generated.
    public var privateKey: Data {
        return a.serialize()
    }

    /// The session key (K) that is exchanged during authentication.
    /// This key can be used to encrypt further communication
    /// between client and server.
    public var sessionKey: Data? {
        guard isAuthenticated else {
            return nil
        }
        return K
    }
}

/// Possible authentication failure modes.
public enum AuthenticationFailure: Error {
    /// Security breach: the provided public key is empty (i.e. PK % N is zero).
    case invalidPublicKey

    /// Invalid client state: call `processChallenge` before `verifySession`.
    case missingChallenge

    /// Failed authentication: the key proof didn't match our own.
    case keyProofMismatch
}

extension AuthenticationFailure: CustomStringConvertible {
    /// A textual representation of this instance.
    ///
    /// Instead of accessing this property directly, convert an instance of any
    /// type to a string by using the `String(describing:)` initializer.
    public var description: String {
        switch self {
        case .invalidPublicKey: return "security breach - the provided public key is invalid"
        case .missingChallenge: return "invalid client state - call `processChallenge` before `verifySession`"
        case .keyProofMismatch: return "failed authentication - the key proof didn't match our own"
        }
    }
}
func ^ (lhs: Data, rhs: Data) -> Data? {
    guard lhs.count == rhs.count else { return nil }
    var result = Data(count: lhs.count)
    for index in lhs.indices {
        result[index] = lhs[index] ^ rhs[index]
    }
    return result
}

// Removed in Xcode 8 beta 3
func + (lhs: Data, rhs: Data) -> Data {
    var result = lhs
    result.append(rhs)
    return result
}
