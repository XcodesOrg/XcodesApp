import Cocoa
import SwiftUI

struct PinCodeTextField: NSViewRepresentable {
    typealias NSViewType = PinCodeTextView

    @Binding var code: String
    let numberOfDigits: Int

    func makeNSView(context: Context) -> NSViewType {
        let view = PinCodeTextView(numberOfDigits: numberOfDigits, itemSpacing: 10)
        view.codeDidChange = { c in code = c  }
        return view
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        nsView.code = (0..<numberOfDigits).map { index in
            if index < code.count {
                let codeIndex = code.index(code.startIndex, offsetBy: index)
                return code[codeIndex]
            } else {
                return nil
            }
        }
    }
}

struct PinCodeTextField_Previews: PreviewProvider {
    struct PreviewContainer: View {
        @State private var code = "1234567890"
        var body: some View {
            PinCodeTextField(code: $code, numberOfDigits: 11)
                .padding()
        }
    }

    static var previews: some View {
        Group {
            PreviewContainer()
        }
    }
}

// MARK: - PinCodeTextView

class PinCodeTextView: NSControl, NSTextFieldDelegate {    
    var code: [Character?] = [] {
        didSet {
            guard code != oldValue else { return }

            if let handler = codeDidChange {
                handler(String(code.compactMap { $0 }))
            }
            updateText()
        }
    }
    var codeDidChange: ((String) -> Void)? = nil
    
    private let numberOfDigits: Int
    private let stackView: NSStackView = .init(frame: .zero)
    private var characterViews: [PinCodeCharacterTextField] = []

    // MARK: - Initializers
    
    init(
        numberOfDigits: Int,
        itemSpacing: CGFloat
    ) {
        self.numberOfDigits = numberOfDigits
        super.init(frame: .zero)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.spacing = itemSpacing
        stackView.orientation = .horizontal
        stackView.distribution = .fillEqually
        stackView.alignment = .centerY
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: self.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor),
            stackView.trailingAnchor.constraint(greaterThanOrEqualTo: self.trailingAnchor),
            stackView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
        ])
        
        self.code = (0..<numberOfDigits).map { _ in nil }
        self.characterViews = (0..<numberOfDigits).map { _ in
            let view = PinCodeCharacterTextField()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.delegate = self
            return view
        }
        characterViews.forEach { 
            stackView.addArrangedSubview($0) 
            stackView.heightAnchor.constraint(equalTo: $0.heightAnchor).isActive = true            
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateText() {
        characterViews.enumerated().forEach { (index, item) in
            if (0..<code.count).contains(index) {
                let _index = code.index(code.startIndex, offsetBy: index)
                item.character = code[_index]
            } else {
                item.character = nil
            }
        }
    }
    
    // MARK: NSTextFieldDelegate
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(deleteBackward(_:)) {
            // If empty, move to previous or first character view
            if textView.string.isEmpty {
                if let lastFieldIndexWithCharacter = code.lastIndex(where: { $0 != nil }) {
                    window?.makeFirstResponder(characterViews[lastFieldIndexWithCharacter])
                } else {
                    window?.makeFirstResponder(characterViews[0])
                }

                return true
            }
        }
        
        // Perform default behaviour
        return false
    }
    
    func controlTextDidChange(_ obj: Notification) {
        guard
            let field = obj.object as? NSTextField,
            isEnabled,
            let fieldIndex = characterViews.firstIndex(where: { $0 === field })
        else { return } 
        
        let newFieldText = field.stringValue

        // If we are focused on the first field and pasting a 6-digit string,
        // treat it as pasting the entire code and focus on the last field
        if code.isEmpty && newFieldText.count == numberOfDigits {
            code = Array(newFieldText)
            window?.makeFirstResponder(characterViews.last)
            return
        }

        let lastCharacter: Character?
        if newFieldText.isEmpty {
            lastCharacter = nil
        } else {
            lastCharacter = newFieldText[newFieldText.index(before: newFieldText.endIndex)]
        }

        code[fieldIndex] = lastCharacter
        
        if lastCharacter != nil {
            if fieldIndex >= characterViews.count - 1 {
                resignFirstResponder()
            } else {
                window?.makeFirstResponder(characterViews[fieldIndex + 1])
            }
        } else {
            if let lastFieldIndexWithCharacter = code.lastIndex(where: { $0 != nil }) {
                window?.makeFirstResponder(characterViews[lastFieldIndexWithCharacter])
            } else {
                window?.makeFirstResponder(characterViews[0])
            }
        }
    }
    
    // MARK: NSResponder
    
    override var acceptsFirstResponder: Bool {
        true
    }
    
    override func becomeFirstResponder() -> Bool {
        characterViews.first?.becomeFirstResponder() ?? false
    }
}

// MARK: - PinCodeCharacterTextField

class PinCodeCharacterTextField: NSTextField {
    var character: Character? = nil {
        didSet {
            stringValue = character.map(String.init) ?? ""
        }
    }
    private var lastSize: NSSize?
    
    init() {
        super.init(frame: .zero)

        wantsLayer = true
        alignment = .center
        maximumNumberOfLines = 1
        font = .boldSystemFont(ofSize: 48)
        
        setContentHuggingPriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .horizontal)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        self.invalidateIntrinsicContentSize()
    }
    
    // This is kinda cheating
    // Assuming that 0 is the widest and tallest character in 0-9
    override var intrinsicContentSize: NSSize {
        var size = NSAttributedString(
            string: "0",
            attributes: [ .font : self.font! ]
        )
        .size()
        // I guess the cell should probably be doing this sizing in order to take into account everything outside of simply the text's frame, but for some reason I can't find a way to do that which works...
        size.width += 16
        size.height += 8
        return size
    }
}
