import SwiftUI

/// A text view that supports NSAttributedStrings, based on NSTextView.
public struct AttributedText: View {
    private let attributedString: NSAttributedString
    private let linkTextAttributes: [NSAttributedString.Key: Any]?
    @State private var actualSize: CGSize = .zero

    public init(_ attributedString: NSAttributedString, linkTextAttributes: [NSAttributedString.Key: Any]? = nil) {
        self.attributedString = attributedString
        self.linkTextAttributes = linkTextAttributes
    }

    public var body: some View {
        InnerAttributedStringText(
            attributedString: attributedString,
            actualSize: $actualSize
        )
        // Limit the height to what's needed for the text
        .frame(height: actualSize.height)
    }
}

// MARK: InnerAttributedStringText

private struct InnerAttributedStringText: NSViewRepresentable {
    private let attributedString: NSAttributedString
    @Binding var actualSize: CGSize

    init(attributedString: NSAttributedString, actualSize: Binding<CGSize>) {
        self.attributedString = attributedString
        _actualSize = actualSize
    }

    func makeNSView(context _: NSViewRepresentableContext<Self>) -> NSTextView {
        let textView = NSTextView()
        textView.backgroundColor = .clear
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.isEditable = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.isSelectable = true

        return textView
    }

    func updateNSView(_ label: NSTextView, context _: NSViewRepresentableContext<Self>) {
        // This must happen on the next run loop so that we don't update the view hierarchy while already in the middle
        // of an update
        Task {
            await Task.yield()
            label.textStorage?.setAttributedString(attributedString)
            // Calculates the height based on the current frame
            label.layoutManager?.ensureLayout(for: label.textContainer!)
            actualSize = label.layoutManager!.usedRect(for: label.textContainer!).size
        }
    }
}

struct AttributedText_Previews: PreviewProvider {
    static var linkExample: NSAttributedString {
        let string = "The next word is a link. This is some more text to test how this wraps when it's too long."
        let attributedString = NSMutableAttributedString(string: string)
        attributedString.addAttribute(
            .link,
            value: URL(string: "https://rhodon.com")!,
            range: NSRange(string.range(of: "link")!, in: string)
        )
        return attributedString
    }

    static var previews: some SwiftUI.View {
        Group {
            // Previews don't work unless they're running, because detecting and setting the size happens on the next
            // run loop
            AttributedText(linkExample)
        }
    }
}
