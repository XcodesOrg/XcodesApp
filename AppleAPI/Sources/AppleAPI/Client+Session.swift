import Foundation

extension Client {
    // MARK: - Session

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

    @MainActor
    func updateSession(serviceKey: String, sessionID: String, scnt: String) async throws -> AuthenticationState {
        _ = try await data(for: URLRequest.trust(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt))
        _ = try await data(for: URLRequest.olympusSession)
        return .authenticated
    }

    @MainActor
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await current.network.data(for: request)
    }

}
