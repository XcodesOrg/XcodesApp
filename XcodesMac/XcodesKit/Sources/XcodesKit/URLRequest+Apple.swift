import Foundation

extension URL {
    static let download = URL(string: "https://developer.apple.com/download")!
    static let downloads = URL(string: "https://developer.apple.com/services-account/QH65B2/downloadws/listDownloads.action")!
    static let downloadXcode = URL(string: "https://developer.apple.com/devcenter/download.action")!
}

extension URLRequest {
    static var download: URLRequest {
        return URLRequest(url: .download)
    }

    static var downloads: URLRequest {
        var request = URLRequest(url: .downloads)
        request.httpMethod = "POST"
        return request
    }

    static func downloadXcode(path: String) -> URLRequest {
        var components = URLComponents(url: .downloadXcode, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        var request = URLRequest(url: components.url!)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["Accept"] = "*/*"
        return request
    }
}
