import os.log
import Foundation

extension Progress {
    var xcodesLocalizedDescription: String {
        return localizedAdditionalDescription.replacingOccurrences(of: " — ", with: "\n")
    }
    func updateFromAria2(string: String) {
            
        let range = NSRange(location: 0, length: string.utf16.count)
        
        // MARK: Total Downloaded
        let regexTotalDownloaded = try! NSRegularExpression(pattern: #"(?<= )(.*)(?=\/)"#)
        
        if let match = regexTotalDownloaded.firstMatch(in: string, options: [], range: range),
            let matchRange = Range(match.range(at: 0), in: string),
            let totalDownloaded = Int(string[matchRange].replacingOccurrences(of: "B", with: "")) {
            self.completedUnitCount = Int64(totalDownloaded)
        }
        
        // MARK: Filesize
        let regexTotalFileSize = try! NSRegularExpression(pattern: #"(?<=/)(.*)(?=\()"#)
            
        if let match = regexTotalFileSize.firstMatch(in: string, options: [], range: range),
           let matchRange = Range(match.range(at: 0), in: string),
           let totalFileSize = Int(string[matchRange].replacingOccurrences(of: "B", with: "")) {
                
            if totalFileSize > 0 {
                self.totalUnitCount = Int64(totalFileSize)
            }
        }
        
        // MARK: PERCENT DOWNLOADED
        // Since we get fractionCompleted from completedUnitCount + totalUnitCount, no need to process
        // let regexPercent = try! NSRegularExpression(pattern: #"((?<percent>\d+)%\))"#)
        
        // MARK: Speed
        let regexSpeed = try! NSRegularExpression(pattern: #"(?<=DL:)(.*)(?= )"#)
                    
        if let match = regexSpeed.firstMatch(in: string, options: [], range: range),
           let matchRange = Range(match.range(at: 0), in: string),
           let speed = Int(string[matchRange].replacingOccurrences(of: "B", with: "")) {
            self.throughput = speed
        } else {
            Logger.appState.debug("Could not parse throughput from aria2 download output")
        }
        
        // MARK: Estimated Time Remaining
        let regexETA = try! NSRegularExpression(pattern: #"(?<=ETA:)(?<hours>\d*h)?(?<minutes>\d*m)?(?<seconds>\d*s)?"#)
        
        if let match = regexETA.firstMatch(in: string, options: [], range: range) {
            var seconds: Int = 0
            
            if let matchRange = Range(match.range(withName: "hours"), in: string),
               let hours = Int(string[matchRange].replacingOccurrences(of: "h", with: "")) {
                seconds += (hours * 60 * 60)
            }
            
            if let matchRange = Range(match.range(withName: "minutes"), in: string),
               let minutes = Int(string[matchRange].replacingOccurrences(of: "m", with: "")) {
                seconds += (minutes * 60)
            }
            
            if let matchRange = Range(match.range(withName: "seconds"), in: string),
               let second = Int(string[matchRange].replacingOccurrences(of: "s", with: "")) {
                seconds += (second)
            }
            
            self.estimatedTimeRemaining = TimeInterval(seconds)
        }
        
    }
    
    func updateFromXcodebuild(text: String) {
        self.totalUnitCount = 100
        self.completedUnitCount = 0
        self.localizedAdditionalDescription = "" // to not show the addtional 

        do {
            
            let downloadPattern = #"(\d+\.\d+)% \(([\d.]+ (?:MB|GB)) of ([\d.]+ GB)\)"#
            let downloadRegex = try NSRegularExpression(pattern: downloadPattern)

            // Search for matches in the text
            if let match = downloadRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                // Extract the percentage - simpler then trying to extract size MB/GB and convert to bytes.
                if let percentRange = Range(match.range(at: 1), in: text), let percentDouble = Double(text[percentRange]) {
                    let percent = Int64(percentDouble.rounded())
                    self.completedUnitCount = percent
                }
            }
            
            // "Downloading tvOS 18.1 Simulator (22J5567a): Installing..." or
            // "Downloading tvOS 18.1 Simulator (22J5567a): Installing (registering download)..."
            if text.range(of: "Installing") != nil {
                // sets the progress to indeterminite to show animating progress
                self.totalUnitCount = 0
                self.completedUnitCount = 0
            }

        } catch {
            Logger.appState.error("Invalid regular expression")
        }
        
    }
}

