import SwiftUI

extension View {
    @ViewBuilder
    func `if`<Other: View>(_ predicate: Bool, then: (Self) -> Other) -> some View {
        if predicate {
            then(self)
        } else {
            self
        }
    }
}
