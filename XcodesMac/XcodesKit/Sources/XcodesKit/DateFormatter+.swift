import Foundation

extension DateFormatter {
    /// Date format used in JSON returned from `URL.downloads`
    static let downloadsDateModified: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy HH:mm"
        return formatter
    }()

    /// Date format used in HTML returned from `URL.download`
    static let downloadsReleaseDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()
}
