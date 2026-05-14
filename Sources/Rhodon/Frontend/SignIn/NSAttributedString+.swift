import AppKit
import Foundation

public extension NSAttributedString {
    func addingAttribute(_ attribute: NSAttributedString.Key, value: Any, range: NSRange) -> NSAttributedString {
        guard let copy = mutableCopy() as? NSMutableAttributedString else { return self }
        copy.addAttribute(attribute, value: value, range: range)
        return copy
    }

    func addingAttribute(_ attribute: NSAttributedString.Key, value: Any) -> NSAttributedString {
        addingAttribute(attribute, value: value, range: NSRange(string.startIndex ..< string.endIndex, in: string))
    }

    /// Detects URLs and adds a NSAttributedString.Key.link attribute with the URL value
    func convertingURLsToLinkAttributes() -> NSAttributedString {
        guard
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
            let copy = mutableCopy() as? NSMutableAttributedString
        else { return self }

        let matches = detector.matches(
            in: string,
            options: [],
            range: NSRange(string.startIndex ..< string.endIndex, in: string)
        )
        for match in matches {
            guard let url = match.url else { continue }
            copy.addAttribute(.link, value: url, range: match.range)
        }

        return copy
    }
}
