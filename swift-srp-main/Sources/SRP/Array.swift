
extension Array where Element: FixedWidthInteger {
    /// create array of random bytes
    static func random(count: Int) -> [Element] {
        var array = self.init()
        for _ in 0..<count {
            array.append(.random(in: Element.min..<Element.max))
        }
        return array
    }

    /// generate a hexdigest of the array of bytes
    func hexdigest() -> String {
        return self.map({
            let characters = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
            return "\(characters[Int($0 >> 4)])\(characters[Int($0 & 0xf)])"
        }).joined()
    }
}

/// xor together the contents of two byte arrays
func ^ (lhs: [UInt8], rhs: [UInt8]) -> [UInt8] {
    precondition(lhs.count == rhs.count, "Arrays are required to be the same size")
    var result = lhs
    for i in 0..<lhs.count {
        result[i] = result[i] ^ rhs[i]
    }
    return result
}
