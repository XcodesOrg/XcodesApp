import SwiftUI

extension View {
    @ViewBuilder
    func isHidden(_ isHidden: Bool) -> some View {
        if isHidden {
            hidden()
        } else {
            self
        }
    }
}

struct ViewIsHiddenPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            Text(verbatim: "Not Hidden")
                .isHidden(false)

            Text(verbatim: "Hidden")
                .isHidden(true)
        }
    }
}
