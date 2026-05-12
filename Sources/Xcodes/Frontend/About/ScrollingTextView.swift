import SwiftUI

struct ScrollingTextView: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    let attributedString: NSAttributedString
    
    func makeNSView(context: Context) -> NSViewType {
        let view = NSTextView.scrollableTextView()
        let textView = view.documentView as? NSTextView
        textView?.isEditable = false
        return view
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        (nsView.documentView as? NSTextView)?.textStorage?.setAttributedString(attributedString)
    }
}

struct ScrollingTextView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollingTextView(attributedString: NSAttributedString(string: "Some sample text"))
    }
}
