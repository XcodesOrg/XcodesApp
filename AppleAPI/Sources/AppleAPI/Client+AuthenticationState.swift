import Foundation

extension Client {
    @MainActor
    func authenticationState(
        data: Data,
        response: URLResponse,
        responseBody: SignInResponse,
        accountName: String,
        serviceKey: String
    ) async throws -> AuthenticationState {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidSession
        }

        switch httpResponse.statusCode {
        case 200:
            _ = try await self.data(for: URLRequest.olympusSession)
            return .authenticated
        case 401:
            throw AuthenticationError.invalidUsernameOrPassword(username: accountName)
        case 403:
            let errorMessage = responseBody.serviceErrors?.first?.description.replacingOccurrences(
                of: "-20209: ",
                with: ""
            ) ?? ""
            throw AuthenticationError.accountLocked(errorMessage)
        case 409:
            return try await handleTwoStepOrFactor(data: data, response: response, serviceKey: serviceKey)
        case 412 where Client.authTypes.contains(responseBody.authType ?? ""):
            throw AuthenticationError.appleIDAndPrivacyAcknowledgementRequired
        default:
            throw AuthenticationError.unexpectedSignInResponse(
                statusCode: httpResponse.statusCode,
                message: responseBody.serviceErrors?.map(\.description).joined(separator: ", ")
            )
        }
    }
}
