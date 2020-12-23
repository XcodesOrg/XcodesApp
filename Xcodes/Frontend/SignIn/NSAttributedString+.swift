import Foundation

public extension NSAttributedString {
    func addingAttribute(_ attribute: NSAttributedString.Key, value: Any, range: NSRange) -> NSAttributedString {
        let copy = mutableCopy() as! NSMutableAttributedString
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
            let copy = self.mutableCopy() as? NSMutableAttributedString
        else { return self }
        
        let matches = detector.matches(in: self.string, options: [], range: NSRange(string.startIndex..<string.endIndex, in: string))
        for match in matches where match.url != nil {
            copy.addAttribute(.link, value: match.url!, range: match.range)
        }

        return copy
    }
}
