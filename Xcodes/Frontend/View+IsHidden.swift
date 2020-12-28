import SwiftUI

extension View {
    @ViewBuilder
    func isHidden(_ isHidden: Bool) -> some View {
        if isHidden {
            self.hidden()
        } else {
            self
        }
    }
}

struct View_IsHidden_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            Text("Not Hidden")
                .isHidden(false)
            
            Text("Hidden")
                .isHidden(true)
        }
    }
}
