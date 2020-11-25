import Foundation

public extension BidirectionalCollection where Element: Equatable {
    func suffix(fromLast delimiter: Element) -> Self.SubSequence {
        guard 
            let lastIndex = lastIndex(of: delimiter),
            index(after: lastIndex) < endIndex
        else { return suffix(0) }
        return suffix(from: index(after: lastIndex))
    }
}

public extension NumberFormatter {
    convenience init(numberStyle: NumberFormatter.Style) {
        self.init()
        self.numberStyle = numberStyle
    }

    func string<N: Numeric>(from number: N) -> String? {
        return string(from: number as! NSNumber)
    }
}

extension Sequence {
    func sorted<Value: Comparable>(_ keyPath: KeyPath<Element, Value>) -> [Element] {
        sorted(by: { $0[keyPath: keyPath] < $1[keyPath: keyPath] })
    }
}
