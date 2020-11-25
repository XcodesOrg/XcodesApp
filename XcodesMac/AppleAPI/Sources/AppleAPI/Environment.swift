import Foundation
import PromiseKit
import PMKFoundation

/**
 Lightweight dependency injection using global mutable state :P

 - SeeAlso: https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
 - SeeAlso: https://www.pointfree.co/episodes/ep18-dependency-injection-made-comfortable
 - SeeAlso: https://vimeo.com/291588126
 */
public struct Environment {
    public var shell = Shell()
    public var network = Network()
    public var logging = Logging()
}

public var Current = Environment()

public struct Shell {
    public var readLine: (String) -> String? = { prompt in
        print(prompt, terminator: "")
        return Swift.readLine()
    }
    public func readLine(prompt: String) -> String? {
        readLine(prompt)
    }
}

public struct Network {
    public var session = URLSession.shared

    public var dataTask: (URLRequestConvertible) -> Promise<(data: Data, response: URLResponse)> = { Current.network.session.dataTask(.promise, with: $0) }
    public func dataTask(with convertible: URLRequestConvertible) -> Promise<(data: Data, response: URLResponse)> {
        dataTask(convertible)
    }
}

public struct Logging {
    public var log: (String) -> Void = { print($0) }
}
