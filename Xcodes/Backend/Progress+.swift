import Foundation

extension Progress {
    var xcodesLocalizedDescription: String {
        return localizedAdditionalDescription.replacingOccurrences(of: " — ", with: "\n")
    }
}
