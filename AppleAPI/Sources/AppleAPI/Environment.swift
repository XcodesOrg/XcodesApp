import Foundation

/**
 Lightweight dependency injection using global mutable state :P

 - SeeAlso: https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
 - SeeAlso: https://www.pointfree.co/episodes/ep18-dependency-injection-made-comfortable
 - SeeAlso: https://vimeo.com/291588126
 */
public struct Environment: Sendable {
    public var network = Network()
}

public let current = Environment()

public struct Network: Sendable {
    public var session = URLSession.shared

    public var data: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(session: URLSession = .shared) {
        self.session = session
        data = { try await session.data(for: $0) }
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(request)
    }
}
