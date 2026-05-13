import Foundation

extension Client {
    @MainActor
    func loadHashcash(accountName: String, serviceKey: String) async throws -> String {
        let request = try URLRequest.federate(account: accountName, serviceKey: serviceKey)
        let (data, response) = try await data(for: request)
        guard let urlResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidSession
        }

        switch urlResponse.statusCode {
        case 200 ..< 300:
            guard
                let bitsString = urlResponse.allHeaderFields["X-Apple-HC-Bits"] as? String,
                let bits = UInt(bitsString),
                let challenge = urlResponse.allHeaderFields["X-Apple-HC-Challenge"] as? String,
                let hashcash = Hashcash().mint(resource: challenge, bits: bits)
            else {
                throw AuthenticationError.invalidHashcash
            }
            return hashcash
        case 400, 401:
            throw AuthenticationError.invalidHashcash
        case let code:
            throw AuthenticationError.badStatusCode(statusCode: code, data: data, response: urlResponse)
        }
    }

}
