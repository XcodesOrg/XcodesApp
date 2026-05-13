import CommonCrypto
import Crypto
import Foundation
import SRP

struct SRPInitContext {
    let serviceKey: String
    let hashcash: String
    let response: ServerSRPInitResponse
}

struct PBKDF2Input {
    let password: String
    let saltData: Data
    let rounds: Int
    let srpProtocol: SRPProtocol
    let keyByteCount = 32
    let prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
}

public final class Client: Sendable {
    static let authTypes = ["sa", "hsa", "non-sa", "hsa2"]

    public init() {}

    // MARK: - Login

    @MainActor
    public func srpLogin(accountName: String, password: String) async throws -> AuthenticationState {
        let session = srpLoginSession()
        let serviceKey = try await loadServiceKey()
        let hashcash = try await loadHashcash(accountName: accountName, serviceKey: serviceKey)
        let srpInit = try await loadSRPInit(
            accountName: accountName,
            serviceKey: serviceKey,
            session: session
        )
        let context = SRPInitContext(serviceKey: serviceKey, hashcash: hashcash, response: srpInit)
        let request = try srpCompleteRequest(
            context: context,
            session: session,
            accountName: accountName,
            password: password
        )
        let (signInData, signInURLResponse) = try await data(for: request)
        let signInResponse = try JSONDecoder().decode(SignInResponse.self, from: signInData)
        return try await authenticationState(
            data: signInData,
            response: signInURLResponse,
            responseBody: signInResponse,
            accountName: accountName,
            serviceKey: serviceKey
        )
    }

}
