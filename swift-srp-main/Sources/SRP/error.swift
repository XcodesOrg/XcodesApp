/// Errors thrown by SRPClient
public enum SRPClientError: Swift.Error {
    /// the key returned by server is invalid, in that either it modulo N is zero or the hash(A,B) is zero
    case nullServerKey
    /// server verification code was wrong
    case invalidServerCode
    /// you called verifyServerCode without a verification key
    case requiresVerificationKey
    /// client key is invalid
    case invalidClientKey
}

/// Errors thrown by SRPServer
///Errors thrown by SRPServer
public enum SRPServerError: Swift.Error {
    /// the modulus of the client key and N generated a zero
    case nullClientKey
    /// client proof of the shared secret was invalid or wrong
    case invalidClientProof
}

