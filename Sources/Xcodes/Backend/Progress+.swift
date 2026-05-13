import Foundation
import os.log
import XcodesKit

extension Progress {
    var xcodesLocalizedDescription: String {
        localizedAdditionalDescription.replacingOccurrences(of: " — ", with: "\n")
    }

    func updateFromAria2(string: String) {
        let range = NSRange(location: 0, length: string.utf16.count)

        // MARK: Total Downloaded

        if let totalDownloaded = aria2IntegerMatch(in: string, range: range, pattern: #"(?<= )(.*)(?=\/)"#) {
            completedUnitCount = Int64(totalDownloaded)
        }

        // MARK: Filesize

        if let totalFileSize = aria2IntegerMatch(in: string, range: range, pattern: #"(?<=/)(.*)(?=\()"#) {
            if totalFileSize > 0 {
                totalUnitCount = Int64(totalFileSize)
            }
        }

        // MARK: PERCENT DOWNLOADED

        // Since we get fractionCompleted from completedUnitCount + totalUnitCount, no need to process
        // let regexPercent = try! NSRegularExpression(pattern: #"((?<percent>\d+)%\))"#)

        // MARK: Speed

        if let speed = aria2IntegerMatch(in: string, range: range, pattern: #"(?<=DL:)(.*)(?= )"#) {
            throughput = speed
        } else {
            Logger.appState.debug("Could not parse throughput from aria2 download output")
        }

        // MARK: Estimated Time Remaining

        updateEstimatedTimeRemainingFromAria2(string: string, range: range)
    }

    private func aria2IntegerMatch(in string: String, range: NSRange, pattern: String) -> Int? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: string, options: [], range: range),
            let matchRange = Range(match.range(at: 0), in: string)
        else {
            return nil
        }

        return Int(string[matchRange].replacingOccurrences(of: "B", with: ""))
    }

    private func updateEstimatedTimeRemainingFromAria2(string: String, range: NSRange) {
        guard let regexETA = try? NSRegularExpression(
            pattern: #"(?<=ETA:)(?<hours>\d*h)?(?<minutes>\d*m)?(?<seconds>\d*s)?"#
        ) else { return }

        if let match = regexETA.firstMatch(in: string, options: [], range: range) {
            var seconds = 0

            if
                let matchRange = Range(match.range(withName: "hours"), in: string),
                let hours = Int(string[matchRange].replacingOccurrences(of: "h", with: "")) {
                seconds += (hours * 60 * 60)
            }

            if
                let matchRange = Range(match.range(withName: "minutes"), in: string),
                let minutes = Int(string[matchRange].replacingOccurrences(of: "m", with: "")) {
                seconds += (minutes * 60)
            }

            if
                let matchRange = Range(match.range(withName: "seconds"), in: string),
                let second = Int(string[matchRange].replacingOccurrences(of: "s", with: "")) {
                seconds += second
            }

            estimatedTimeRemaining = TimeInterval(seconds)
        }
    }

    func updateFromXcodebuild(text: String) {
        totalUnitCount = 100
        completedUnitCount = 0
        localizedAdditionalDescription = "" // to not show the addtional

        do {
            let downloadPattern = #"(\d+\.\d+)% \(([\d.]+ (?:MB|GB)) of ([\d.]+ GB)\)"#
            let downloadRegex = try NSRegularExpression(pattern: downloadPattern)

            // Search for matches in the text
            if let match = downloadRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                // Extract the percentage - simpler then trying to extract size MB/GB and convert to bytes.
                if
                    let percentRange = Range(match.range(at: 1), in: text),
                    let percentDouble = Double(text[percentRange]) {
                    let percent = Int64(percentDouble.rounded())
                    completedUnitCount = percent
                }
            }

            // "Downloading tvOS 18.1 Simulator (22J5567a): Installing..." or
            // "Downloading tvOS 18.1 Simulator (22J5567a): Installing (registering download)..."
            if text.range(of: "Installing") != nil {
                // sets the progress to indeterminite to show animating progress
                totalUnitCount = 0
                completedUnitCount = 0
            }

        } catch {
            Logger.appState.error("Invalid regular expression")
        }
    }
}
