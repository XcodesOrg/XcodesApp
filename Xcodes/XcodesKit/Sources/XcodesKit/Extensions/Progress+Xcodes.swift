import Foundation

public extension Progress {
    func updateFromAria2(string: String) {
        let range = NSRange(location: 0, length: string.utf16.count)

        let regexTotalDownloaded = try! NSRegularExpression(pattern: #"(?<= )(.*)(?=\/)"#)
        if let match = regexTotalDownloaded.firstMatch(in: string, options: [], range: range),
            let matchRange = Range(match.range(at: 0), in: string),
            let totalDownloaded = Int(string[matchRange].replacingOccurrences(of: "B", with: ""))
        {
            completedUnitCount = Int64(totalDownloaded)
        }

        let regexTotalFileSize = try! NSRegularExpression(pattern: #"(?<=/)(.*)(?=\()"#)
        if let match = regexTotalFileSize.firstMatch(in: string, options: [], range: range),
            let matchRange = Range(match.range(at: 0), in: string),
            let totalFileSize = Int(string[matchRange].replacingOccurrences(of: "B", with: "")),
            totalFileSize > 0
        {
            totalUnitCount = Int64(totalFileSize)
        }

        let regexSpeed = try! NSRegularExpression(pattern: #"(?<=DL:)(.*)(?= )"#)
        if let match = regexSpeed.firstMatch(in: string, options: [], range: range),
            let matchRange = Range(match.range(at: 0), in: string),
            let speed = Int(string[matchRange].replacingOccurrences(of: "B", with: ""))
        {
            throughput = speed
        }

        let regexETA = try! NSRegularExpression(pattern: #"(?<=ETA:)(?<hours>\d*h)?(?<minutes>\d*m)?(?<seconds>\d*s)?"#)
        if let match = regexETA.firstMatch(in: string, options: [], range: range) {
            var seconds = 0

            if let matchRange = Range(match.range(withName: "hours"), in: string),
                let hours = Int(string[matchRange].replacingOccurrences(of: "h", with: ""))
            {
                seconds += hours * 60 * 60
            }

            if let matchRange = Range(match.range(withName: "minutes"), in: string),
                let minutes = Int(string[matchRange].replacingOccurrences(of: "m", with: ""))
            {
                seconds += minutes * 60
            }

            if let matchRange = Range(match.range(withName: "seconds"), in: string),
                let second = Int(string[matchRange].replacingOccurrences(of: "s", with: ""))
            {
                seconds += second
            }

            estimatedTimeRemaining = TimeInterval(seconds)
        }
    }

    func updateFromXcodebuild(text: String) {
        totalUnitCount = 100
        completedUnitCount = 0
        localizedAdditionalDescription = ""

        let downloadPattern = #"(\d+\.\d+)% \(([\d.]+ (?:MB|GB)) of ([\d.]+ GB)\)"#
        let downloadRegex = try! NSRegularExpression(pattern: downloadPattern)

        if let match = downloadRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let percentRange = Range(match.range(at: 1), in: text),
            let percentDouble = Double(text[percentRange])
        {
            completedUnitCount = Int64(percentDouble.rounded())
        }

        if text.range(of: "Installing") != nil {
            totalUnitCount = 0
            completedUnitCount = 0
        }
    }
}
