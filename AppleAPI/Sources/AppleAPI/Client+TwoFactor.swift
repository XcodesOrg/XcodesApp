import Foundation

extension Client {
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
            return try handleTwoFactor(
                serviceKey: serviceKey,
                sessionID: sessionID,
                scnt: scnt,
                authOptions: authOptions
            )
        case .securityKey:
            throw AuthenticationError.accountUsesSecurityKeyAuthentication
        case .unknown:
            let possibleResponseString = String(data: data, encoding: .utf8)
            throw AuthenticationError.accountUsesUnknownAuthenticationKind(possibleResponseString)
        }
    }

    @MainActor
    func handleTwoFactor(
        serviceKey: String,
        sessionID: String,
        scnt: String,
        authOptions: AuthOptionsResponse
    ) throws -> AuthenticationState {
        let option: TwoFactorOption
        if authOptions.smsAutomaticallySent {
            guard let trustedPhoneNumber = authOptions.trustedPhoneNumbers?.first else {
                throw AuthenticationError.missingTrustedPhoneNumber
            }
            option = .smsSent(trustedPhoneNumber)
        } else if authOptions.canFallBackToSMS {
            option = .smsPendingChoice
        } else {
            option = .codeSent
        }

        let sessionData = AppleSessionData(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
        return .waitingForSecondFactor(option, authOptions, sessionData)
    }

    // MARK: - Continue 2FA

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

}
