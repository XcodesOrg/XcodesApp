import Combine
import Crypto
import Foundation
import SRP

struct SRPLoginSession {
    let client: SRPClient<SHA256>
    let clientKeys: SRPKeyPair

    var publicKey: SRPKey {
        clientKeys.public
    }
}

struct SRPDecodedChallenge {
    let serverPublicKey: Data
    let salt: Data
    let encryptedPassword: Data
}

struct SRPProofPair {
    let clientProof: String
    let serverProof: String
}

extension Client {
    func srpLoginSession() -> SRPLoginSession {
        let client = SRPClient(configuration: SRPConfiguration<SHA256>(.N2048))
        return SRPLoginSession(client: client, clientKeys: client.generateKeys())
    }

    func serviceKeyAndHashcashPublisher(accountName: String) -> AnyPublisher<(String, String), Swift.Error> {
        current.network.dataTask(with: URLRequest.itcServiceKey)
            .map(\.data)
            .decode(type: ServiceKeyResponse.self, decoder: JSONDecoder())
            .flatMap { serviceKeyResponse -> AnyPublisher<(String, String), Swift.Error> in
                let serviceKey = serviceKeyResponse.authServiceKey
                return self.loadHashcash(accountName: accountName, serviceKey: serviceKey)
                    .map { (serviceKey, $0) }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func srpInitPublisher(
        accountName: String,
        serviceKey: String,
        hashcash: String,
        session: SRPLoginSession
    ) -> AnyPublisher<SRPInitContext, Swift.Error> {
        current.network.dataTask(with: srpInitRequest(
            accountName: accountName,
            serviceKey: serviceKey,
            session: session
        ))
        .map(\.data)
        .decode(type: ServerSRPInitResponse.self, decoder: JSONDecoder())
        .map { SRPInitContext(serviceKey: serviceKey, hashcash: hashcash, response: $0) }
        .eraseToAnyPublisher()
    }

    func srpCompletePublisher(
        context: SRPInitContext,
        session: SRPLoginSession,
        accountName: String,
        password: String
    ) -> AnyPublisher<URLSession.DataTaskPublisher.Output, Swift.Error> {
        Result {
            try srpCompleteRequest(
                context: context,
                session: session,
                accountName: accountName,
                password: password
            )
        }
        .publisher
        .flatMap { current.network.dataTask(with: $0).mapError { $0 as Swift.Error } }
        .eraseToAnyPublisher()
    }

    @MainActor
    func loadServiceKey() async throws -> String {
        let serviceKeyData = try await data(for: URLRequest.itcServiceKey).0
        return try JSONDecoder().decode(ServiceKeyResponse.self, from: serviceKeyData).authServiceKey
    }

    @MainActor
    func loadSRPInit(
        accountName: String,
        serviceKey: String,
        session: SRPLoginSession
    ) async throws -> ServerSRPInitResponse {
        let srpInitData = try await data(for: srpInitRequest(
            accountName: accountName,
            serviceKey: serviceKey,
            session: session
        )).0
        return try JSONDecoder().decode(ServerSRPInitResponse.self, from: srpInitData)
    }

    func srpInitRequest(accountName: String, serviceKey: String, session: SRPLoginSession) -> URLRequest {
        URLRequest.SRPInit(
            serviceKey: serviceKey,
            publicKey: Data(session.publicKey.bytes).base64EncodedString(),
            accountName: accountName
        )
    }

    func srpCompleteRequest(
        context: SRPInitContext,
        session: SRPLoginSession,
        accountName: String,
        password: String
    ) throws -> URLRequest {
        let proofs = try srpProofs(
            response: context.response,
            session: session,
            accountName: accountName,
            password: password
        )
        return URLRequest.SRPComplete(
            serviceKey: context.serviceKey,
            hashcash: context.hashcash,
            payload: SRPCompletePayload(
                accountName: accountName,
                challenge: context.response.challenge,
                clientProof: proofs.clientProof,
                serverProof: proofs.serverProof
            )
        )
    }

    func srpProofs(
        response: ServerSRPInitResponse,
        session: SRPLoginSession,
        accountName: String,
        password: String
    ) throws -> SRPProofPair {
        let challenge = try srpDecodedChallenge(response: response, password: password)
        let sharedSecret = try srpSharedSecret(challenge: challenge, session: session)
        let clientProof = session.client.calculateClientProof(
            username: accountName,
            salt: [UInt8](challenge.salt),
            clientPublicKey: session.publicKey,
            serverPublicKey: .init([UInt8](challenge.serverPublicKey)),
            sharedSecret: .init(sharedSecret.bytes)
        )
        let serverProof = session.client.calculateServerProof(
            clientPublicKey: session.publicKey,
            clientProof: clientProof,
            sharedSecret: .init([UInt8](sharedSecret.bytes))
        )
        return SRPProofPair(
            clientProof: Data(clientProof).base64EncodedString(),
            serverProof: Data(serverProof).base64EncodedString()
        )
    }

    func srpDecodedChallenge(response: ServerSRPInitResponse, password: String) throws -> SRPDecodedChallenge {
        guard
            let decodedB = Data(base64Encoded: response.serverPublicKey),
            let decodedSalt = Data(base64Encoded: response.salt),
            let encryptedPassword = pbkdf2(PBKDF2Input(
                password: password,
                saltData: decodedSalt,
                rounds: response.iteration,
                srpProtocol: response.protocol
            ))
        else {
            throw AuthenticationError.srpInvalidPublicKey
        }

        return SRPDecodedChallenge(
            serverPublicKey: decodedB,
            salt: decodedSalt,
            encryptedPassword: encryptedPassword
        )
    }

    func srpSharedSecret(challenge: SRPDecodedChallenge, session: SRPLoginSession) throws -> SRPKey {
        do {
            return try session.client.calculateSharedSecret(
                password: [UInt8](challenge.encryptedPassword),
                salt: [UInt8](challenge.salt),
                clientKeys: session.clientKeys,
                serverPublicKey: .init([UInt8](challenge.serverPublicKey))
            )
        } catch {
            throw AuthenticationError.srpInvalidPublicKey
        }
    }
}
