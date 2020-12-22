import Foundation
import Combine

/**
 Lightweight dependency injection using global mutable state :P

 - SeeAlso: https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
 - SeeAlso: https://www.pointfree.co/episodes/ep18-dependency-injection-made-comfortable
 - SeeAlso: https://vimeo.com/291588126
 */
public struct Environment {
    public var network = Network()
    public var logging = Logging()
}

public var Current = Environment()

public struct Network {
    public var session = URLSession.shared

    public var dataTask: (URLRequest) -> URLSession.DataTaskPublisher = { Current.network.session.dataTaskPublisher(for: $0) }
    public func dataTask(with request: URLRequest) -> URLSession.DataTaskPublisher {
        dataTask(request)
    }
}

public struct Logging {
    public var log: (String) -> Void = { print($0) }
}
