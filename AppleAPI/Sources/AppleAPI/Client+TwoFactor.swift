import Combine
import Foundation

extension Client {
    func handleTwoStepOrFactor(
        data: Data,
        response: URLResponse,
        serviceKey: String
    ) -> AnyPublisher<AuthenticationState, Swift.Error> {
        guard
            let httpResponse = response as? HTTPURLResponse,
            let sessionID = httpResponse.allHeaderFields["X-Apple-ID-Session-Id"] as? String,
            let scnt = httpResponse.allHeaderFields["scnt"] as? String
        else {
            return Fail(error: AuthenticationError.invalidSession).eraseToAnyPublisher()
        }

        return current.network.dataTask(with: URLRequest.authOptions(
            serviceKey: serviceKey,
            sessionID: sessionID,
            scnt: scnt
        ))
        .map(\.data)
        .decode(type: AuthOptionsResponse.self, decoder: JSONDecoder())
        .flatMap { authOptions -> AnyPublisher<AuthenticationState, Error> in
            switch authOptions.kind {
            case .twoStep:
                return Fail(error: AuthenticationError.accountUsesTwoStepAuthentication)
                    .eraseToAnyPublisher()
            case .twoFactor:
                return self.handleTwoFactor(
                    serviceKey: serviceKey,
                    sessionID: sessionID,
                    scnt: scnt,
                    authOptions: authOptions
                )
                .eraseToAnyPublisher()
            case .securityKey:
                return Fail(error: AuthenticationError.accountUsesSecurityKeyAuthentication)
                    .eraseToAnyPublisher()
            case .unknown:
                let possibleResponseString = String(data: data, encoding: .utf8)
                return Fail(error: AuthenticationError.accountUsesUnknownAuthenticationKind(possibleResponseString))
                    .eraseToAnyPublisher()
            }
        }
        .eraseToAnyPublisher()
    }

    @MainActor
    func handleTwoStepOrFactor(
        data: Data,
        response: URLResponse,
        serviceKey: String
    ) async throws -> AuthenticationState {
        guard
            let httpResponse = response as? HTTPURLResponse,
            let sessionID = httpResponse.allHeaderFields["X-Apple-ID-Session-Id"] as? String,
            let scnt = httpResponse.allHeaderFields["scnt"] as? String
        else {
            throw AuthenticationError.invalidSession
        }
        let authOptionsData = try await self.data(for: URLRequest.authOptions(
            serviceKey: serviceKey,
            sessionID: sessionID,
            scnt: scnt
        )).0
        let authOptions = try JSONDecoder().decode(AuthOptionsResponse.self, from: authOptionsData)

        switch authOptions.kind {
        case .twoStep:
            throw AuthenticationError.accountUsesTwoStepAuthentication
        case .twoFactor:
            return handleTwoFactor(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt, authOptions: authOptions)
        case .securityKey:
            throw AuthenticationError.accountUsesSecurityKeyAuthentication
        case .unknown:
            let possibleResponseString = String(data: data, encoding: .utf8)
            throw AuthenticationError.accountUsesUnknownAuthenticationKind(possibleResponseString)
        }
    }

    func handleTwoFactor(
        serviceKey: String,
        sessionID: String,
        scnt: String,
        authOptions: AuthOptionsResponse
    ) -> AnyPublisher<AuthenticationState, Error> {
        let option: TwoFactorOption

            // SMS was sent automatically
            = if authOptions.smsAutomaticallySent {
            .smsSent(authOptions.trustedPhoneNumbers!.first!)
            // SMS wasn't sent automatically because user needs to choose a phone to send to
        } else if authOptions.canFallBackToSMS {
            .smsPendingChoice
            // Code is shown on trusted devices
        } else {
            .codeSent
        }

        let sessionData = AppleSessionData(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
        return Just(AuthenticationState.waitingForSecondFactor(option, authOptions, sessionData))
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    @MainActor
    func handleTwoFactor(
        serviceKey: String,
        sessionID: String,
        scnt: String,
        authOptions: AuthOptionsResponse
    ) -> AuthenticationState {
        let option: TwoFactorOption = if authOptions.smsAutomaticallySent {
            .smsSent(authOptions.trustedPhoneNumbers!.first!)
        } else if authOptions.canFallBackToSMS {
            .smsPendingChoice
        } else {
            .codeSent
        }

        let sessionData = AppleSessionData(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
        return .waitingForSecondFactor(option, authOptions, sessionData)
    }

    // MARK: - Continue 2FA

    public func requestSMSSecurityCode(
        to trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber,
        authOptions: AuthOptionsResponse,
        sessionData: AppleSessionData
    ) -> AnyPublisher<AuthenticationState, Error> {
        Result {
            try URLRequest.requestSecurityCode(
                serviceKey: sessionData.serviceKey,
                sessionID: sessionData.sessionID,
                scnt: sessionData.scnt,
                trustedPhoneID: trustedPhoneNumber.id
            )
        }
        .publisher
        .flatMap { request in
            current.network.dataTask(with: request)
                .mapError { $0 as Error }
        }
        .map { _ in AuthenticationState.waitingForSecondFactor(.smsSent(trustedPhoneNumber), authOptions, sessionData) }
        .eraseToAnyPublisher()
    }

    @MainActor
    public func requestSMSSecurityCode(
        to trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber,
        authOptions: AuthOptionsResponse,
        sessionData: AppleSessionData
    ) async throws -> AuthenticationState {
        let request = try URLRequest.requestSecurityCode(
            serviceKey: sessionData.serviceKey,
            sessionID: sessionData.sessionID,
            scnt: sessionData.scnt,
            trustedPhoneID: trustedPhoneNumber.id
        )
        _ = try await data(for: request)
        return .waitingForSecondFactor(.smsSent(trustedPhoneNumber), authOptions, sessionData)
    }

    public func submitSecurityCode(
        _ code: SecurityCode,
        sessionData: AppleSessionData
    ) -> AnyPublisher<AuthenticationState, Error> {
        Result {
            try URLRequest.submitSecurityCode(
                serviceKey: sessionData.serviceKey,
                sessionID: sessionData.sessionID,
                scnt: sessionData.scnt,
                code: code
            )
        }
        .publisher
        .flatMap { request in
            current.network.dataTask(with: request)
                .mapError { $0 as Error }
                .tryMap { data, response throws -> (Data, URLResponse) in
                    guard let urlResponse = response as? HTTPURLResponse else { return (data, response) }
                    switch urlResponse.statusCode {
                    case 200 ..< 300:
                        return (data, urlResponse)
                    case 400, 401:
                        throw AuthenticationError.incorrectSecurityCode
                    case 412:
                        throw AuthenticationError.appleIDAndPrivacyAcknowledgementRequired
                    case let code:
                        throw AuthenticationError.badStatusCode(statusCode: code, data: data, response: urlResponse)
                    }
                }
                .flatMap { _, _ -> AnyPublisher<AuthenticationState, Error> in
                    self.updateSession(
                        serviceKey: sessionData.serviceKey,
                        sessionID: sessionData.sessionID,
                        scnt: sessionData.scnt
                    )
                }
        }
        .eraseToAnyPublisher()
    }

    @MainActor
    public func submitSecurityCode(
        _ code: SecurityCode,
        sessionData: AppleSessionData
    ) async throws -> AuthenticationState {
        let request = try URLRequest.submitSecurityCode(
            serviceKey: sessionData.serviceKey,
            sessionID: sessionData.sessionID,
            scnt: sessionData.scnt,
            code: code
        )
        let (data, response) = try await self.data(for: request)
        if let urlResponse = response as? HTTPURLResponse {
            switch urlResponse.statusCode {
            case 200 ..< 300:
                break
            case 400, 401:
                throw AuthenticationError.incorrectSecurityCode
            case 412:
                throw AuthenticationError.appleIDAndPrivacyAcknowledgementRequired
            case let code:
                throw AuthenticationError.badStatusCode(statusCode: code, data: data, response: urlResponse)
            }
        }
        return try await updateSession(
            serviceKey: sessionData.serviceKey,
            sessionID: sessionData.sessionID,
            scnt: sessionData.scnt
        )
    }

    public func submitChallenge(
        response: Data,
        sessionData: AppleSessionData
    ) -> AnyPublisher<AuthenticationState, Error> {
        Result {
            URLRequest.respondToChallenge(
                serviceKey: sessionData.serviceKey,
                sessionID: sessionData.sessionID,
                scnt: sessionData.scnt,
                response: response
            )
        }
        .publisher
        .flatMap { request in
            current.network.dataTask(with: request)
                .mapError { $0 as Error }
                .tryMap { data, response throws -> (Data, URLResponse) in
                    guard let urlResponse = response as? HTTPURLResponse else { return (data, response) }
                    switch urlResponse.statusCode {
                    case 200 ..< 300:
                        return (data, urlResponse)
                    case 400, 401:
                        throw AuthenticationError.incorrectSecurityCode
                    case 412:
                        throw AuthenticationError.appleIDAndPrivacyAcknowledgementRequired
                    case let code:
                        throw AuthenticationError.badStatusCode(statusCode: code, data: data, response: urlResponse)
                    }
                }
                .flatMap { _, _ -> AnyPublisher<AuthenticationState, Error> in
                    self.updateSession(
                        serviceKey: sessionData.serviceKey,
                        sessionID: sessionData.sessionID,
                        scnt: sessionData.scnt
                    )
                }
        }.eraseToAnyPublisher()
    }

}
