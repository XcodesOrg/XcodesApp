import Combine
import Foundation

extension Client {
    func authenticationStatePublisher(
        data: Data,
        response: URLResponse,
        accountName: String,
        serviceKey: String
    ) -> AnyPublisher<AuthenticationState, Swift.Error> {
        Just(data)
            .decode(type: SignInResponse.self, decoder: JSONDecoder())
            .flatMap { responseBody -> AnyPublisher<AuthenticationState, Swift.Error> in
                self.authenticationStatePublisher(
                    responseBody: responseBody,
                    data: data,
                    response: response,
                    accountName: accountName,
                    serviceKey: serviceKey
                )
            }
            .eraseToAnyPublisher()
    }

    func authenticationStatePublisher(
        responseBody: SignInResponse,
        data: Data,
        response: URLResponse,
        accountName: String,
        serviceKey: String
    ) -> AnyPublisher<AuthenticationState, Swift.Error> {
        guard let httpResponse = response as? HTTPURLResponse else {
            return Fail(error: AuthenticationError.invalidSession).eraseToAnyPublisher()
        }

        switch httpResponse.statusCode {
        case 200:
            return current.network.dataTask(with: URLRequest.olympusSession)
                .map { _ in AuthenticationState.authenticated }
                .mapError { $0 as Swift.Error }
                .eraseToAnyPublisher()
        case 401:
            return Fail(error: AuthenticationError.invalidUsernameOrPassword(username: accountName))
                .eraseToAnyPublisher()
        case 403:
            let errorMessage = responseBody.serviceErrors?.first?.description.replacingOccurrences(
                of: "-20209: ",
                with: ""
            ) ?? ""
            return Fail(error: AuthenticationError.accountLocked(errorMessage))
                .eraseToAnyPublisher()
        case 409:
            return handleTwoStepOrFactor(data: data, response: response, serviceKey: serviceKey)
        case 412 where Client.authTypes.contains(responseBody.authType ?? ""):
            return Fail(error: AuthenticationError.appleIDAndPrivacyAcknowledgementRequired)
                .eraseToAnyPublisher()
        default:
            return Fail(error: AuthenticationError.unexpectedSignInResponse(
                statusCode: httpResponse.statusCode,
                message: responseBody.serviceErrors?.map(\.description).joined(separator: ", ")
            ))
            .eraseToAnyPublisher()
        }
    }

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
