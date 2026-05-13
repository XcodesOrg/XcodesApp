import Combine
import Foundation

extension Client {
    // MARK: - Session

    /// Use the olympus session endpoint to see if the existing session is still valid
    public func validateSession() -> AnyPublisher<Void, Error> {
        current.network.dataTask(with: URLRequest.olympusSession)
            .tryMap { result -> Data in
                guard let httpResponse = result.response as? HTTPURLResponse else {
                    throw AuthenticationError.invalidSession
                }
                if httpResponse.statusCode == 401 {
                    throw AuthenticationError.notAuthorized
                }

                return result.data
            }
            .decode(type: AppleSession.self, decoder: JSONDecoder())
            .tryMap { _ in
                // A user that is a non-paid Apple Developer will have a provider == nil
                // Those users can still download Xcode.
                // Non Apple Developers will get caught in the download as invalid
//                if session.provider == nil {
//                    throw AuthenticationError.notDeveloperAppleId
//                }
            }
            .eraseToAnyPublisher()
    }

    @MainActor
    public func validateSession() async throws {
        let (data, response) = try await self.data(for: URLRequest.olympusSession)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidSession
        }
        if httpResponse.statusCode == 401 {
            throw AuthenticationError.notAuthorized
        }

        _ = try JSONDecoder().decode(AppleSession.self, from: data)
    }

    func updateSession(
        serviceKey: String,
        sessionID: String,
        scnt: String
    ) -> AnyPublisher<AuthenticationState, Error> {
        current.network.dataTask(with: URLRequest.trust(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt))
            .flatMap { _, _ in
                current.network.dataTask(with: URLRequest.olympusSession)
                    .map { _ in AuthenticationState.authenticated }
            }
            .mapError { $0 as Error }
            .eraseToAnyPublisher()
    }

    @MainActor
    func updateSession(serviceKey: String, sessionID: String, scnt: String) async throws -> AuthenticationState {
        _ = try await data(for: URLRequest.trust(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt))
        _ = try await data(for: URLRequest.olympusSession)
        return .authenticated
    }

    @MainActor
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await current.network.session.data(for: request)
    }

}
