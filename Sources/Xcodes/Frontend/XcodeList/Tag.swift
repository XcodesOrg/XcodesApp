import SwiftUI

struct Tag: View {
    var text: String
    var body: some View {
        Text(text)
            .foregroundColor(.white)
            .background(RoundedRectangle(cornerRadius: 3).padding([.leading, .trailing], -3))
    }
}

struct Tag_Previews: PreviewProvider {
    static var previews: some View {
        Tag(text: "SELECTED")
            .foregroundColor(.green)
            .padding()
    }
}
