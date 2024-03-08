import SwiftUI

struct AcknowledgmentsView: View {
    
    var body: some View {
        ScrollingTextView(
            attributedString: NSAttributedString(
                rtf: try! Data(contentsOf: Bundle.main.url(forResource: "Licenses", withExtension: "rtf")!), 
                documentAttributes: nil
            )!
            .addingAttribute(.foregroundColor, value: NSColor.labelColor)
        )
        .frame(minWidth: 600, minHeight: 500)
    }
}


struct AcknowledgementsView_Previews: PreviewProvider {
    static var previews: some View {
        AcknowledgmentsView()
    }
}
