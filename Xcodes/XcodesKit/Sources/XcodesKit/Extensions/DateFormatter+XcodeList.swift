import Foundation

public extension DateFormatter {
    static let downloadsDateModified: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = .init(identifier: .iso8601)
        return formatter
    }()

    static let downloadsReleaseDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()
}
