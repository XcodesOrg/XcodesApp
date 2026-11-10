import SwiftUI

struct AcknowledgmentsView: View {
    
    var body: some View {
        ScrollingTextView(
            attributedString: acknowledgements
        )
        .frame(minWidth: 600, minHeight: 500)
    }

    private var acknowledgements: NSAttributedString {
        let text = NSMutableAttributedString(attributedString: NSAttributedString(
            rtf: try! Data(contentsOf: Bundle.main.url(forResource: "Licenses", withExtension: "rtf")!),
            documentAttributes: nil
        )!)
        if let url = Bundle.main.url(forResource: "XcodesCleanupKitNotices", withExtension: "txt"),
           let notices = try? String(contentsOf: url, encoding: .utf8) {
            text.append(NSAttributedString(string: "\n\n" + notices))
        }
        return text.addingAttribute(.foregroundColor, value: NSColor.labelColor)
    }
}


struct AcknowledgementsView_Previews: PreviewProvider {
    static var previews: some View {
        AcknowledgmentsView()
    }
}
