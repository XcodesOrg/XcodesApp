import SwiftUI

struct AcknowledgmentsView: View {
    
    var body: some View {
        ScrollingTextView(
            attributedString: Self.licensesAttributedString()
        )
        .frame(minWidth: 600, minHeight: 500)
    }

    private static func licensesAttributedString() -> NSAttributedString {
        let url = Bundle.main.url(forResource: "Licenses", withExtension: "md")!
        let markdown = try! String(contentsOf: url, encoding: .utf8)
        let attributedString = (try? AttributedString(markdown: markdown))
            .map(NSAttributedString.init)
            ?? NSAttributedString(string: markdown)
        return attributedString.addingAttribute(.foregroundColor, value: NSColor.labelColor)
    }
}


struct AcknowledgementsView_Previews: PreviewProvider {
    static var previews: some View {
        AcknowledgmentsView()
    }
}
