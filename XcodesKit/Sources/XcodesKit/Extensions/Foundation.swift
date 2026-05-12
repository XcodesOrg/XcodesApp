import Foundation

extension NSRegularExpression {
    func firstString(in string: String, options: NSRegularExpression.MatchingOptions = []) -> String? {
      let range = NSRange(location: 0, length: string.utf16.count)
      guard let firstMatch = firstMatch(in: string, options: options, range: range),
            let resultRange = Range(firstMatch.range, in: string) else {
        return nil
      }
      return String(string[resultRange])
    }
}
