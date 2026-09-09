import Cocoa
import SwiftUI

struct PinCodeTextField: NSViewRepresentable {
    typealias NSViewType = PinCodeTextView

    @Binding var code: String
    let numberOfDigits: Int
    let complete: (String) -> Void

    func makeNSView(context: Context) -> NSViewType {
        let view = PinCodeTextView(numberOfDigits: numberOfDigits, itemSpacing: 10)
        view.codeDidChange = { c in code = c }
        view.codeDidComplete = { complete($0) }
        return view
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {
        nsView.setCode(code)
    }
}

struct PinCodeTextField_Previews: PreviewProvider {
    struct PreviewContainer: View {
        @State private var code = "1234567890"
        var body: some View {
            PinCodeTextField(code: $code, numberOfDigits: 11) {
                print("Input is complete \($0)")
            }.padding()
        }
    }

    static var previews: some View {
        Group {
            PreviewContainer()
        }
    }
}

// MARK: - PinCodeTextView

/// A single hidden text field receives all input (so pasting and macOS one-time-code
/// autofill insert the whole code at once) while the per-digit boxes are display-only
class PinCodeTextView: NSControl, NSTextFieldDelegate {
    var codeDidChange: ((String) -> Void)? = nil
    var codeDidComplete: ((String) -> Void)? = nil

    private(set) var currentCode = ""

    private let numberOfDigits: Int
    private let stackView: NSStackView = .init(frame: .zero)
    private var characterBoxes: [PinCodeCharacterBox] = []
    private let inputField = PinCodeInputField()
    private var firstResponderObservation: NSKeyValueObservation?

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

        self.characterBoxes = (0..<numberOfDigits).map { _ in
            let view = PinCodeCharacterBox()
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        }
        characterBoxes.forEach {
            stackView.addArrangedSubview($0)
            stackView.heightAnchor.constraint(equalTo: $0.heightAnchor).isActive = true
        }

        // The invisible input field sits on top of the boxes so it gets all
        // clicks and keyboard input, and anchors the system autofill suggestion
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.delegate = self
        addSubview(inputField)
        NSLayoutConstraint.activate([
            inputField.topAnchor.constraint(equalTo: self.topAnchor),
            inputField.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            inputField.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            inputField.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])

        updateBoxes()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCode(_ newCode: String) {
        let sanitized = sanitize(newCode)
        guard sanitized != currentCode else { return }
        currentCode = sanitized
        if inputField.stringValue != sanitized {
            inputField.stringValue = sanitized
        }
        updateBoxes()
    }

    private func sanitize(_ string: String) -> String {
        String(string.filter { $0.isLetter || $0.isNumber }.prefix(numberOfDigits))
    }

    private func updateBoxes() {
        let characters = Array(currentCode)
        let activeIndex = isInputFocused ? min(characters.count, numberOfDigits - 1) : nil
        characterBoxes.enumerated().forEach { (index, box) in
            box.character = index < characters.count ? characters[index] : nil
            box.isActive = index == activeIndex
        }
    }

    private var isInputFocused: Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder === inputField { return true }
        if let editor = responder as? NSTextView, editor.delegate === inputField { return true }
        return false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        firstResponderObservation = window?.observe(\.firstResponder) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateBoxes() }
        }
        // Focus immediately so the system one-time-code suggestion can appear
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            if window.firstResponder === window {
                window.makeFirstResponder(self.inputField)
            }
        }
    }

    // Returns the contiguous run of characters added between old and new,
    // assuming a single insertion (typing, paste or autofill)
    private func insertedText(from old: String, to new: String) -> String? {
        guard new.count > old.count else { return nil }
        let oldChars = Array(old)
        let newChars = Array(new)
        var prefix = 0
        while prefix < oldChars.count, oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldChars.count - prefix,
              oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
            suffix += 1
        }
        return String(newChars[prefix..<(newChars.count - suffix)])
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard isEnabled else { return }

        let rawText = inputField.stringValue
        let sanitized: String

        // If a full code was pasted or autofilled while digits were already
        // entered, the pasted code wins over the leftover digits
        if let inserted = insertedText(from: currentCode, to: rawText),
           inserted.count > 1,
           sanitize(inserted).count == numberOfDigits {
            sanitized = sanitize(inserted)
        } else {
            sanitized = sanitize(rawText)
        }

        if inputField.stringValue != sanitized {
            inputField.stringValue = sanitized
        }

        guard sanitized != currentCode else { return }
        currentCode = sanitized
        updateBoxes()

        codeDidChange?(sanitized)
        if sanitized.count == numberOfDigits {
            codeDidComplete?(sanitized)
        }
    }

    // MARK: NSResponder

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        inputField.becomeFirstResponder()
    }

    override var isEnabled: Bool {
        didSet { inputField.isEnabled = isEnabled }
    }
}

// MARK: - PinCodeInputField

/// Invisible single-line field that owns the actual text input.
/// `.oneTimeCode` lets macOS offer 2FA codes from Messages/Mail
private class PinCodeInputField: NSTextField {
    init() {
        super.init(frame: .zero)

        isBordered = false
        drawsBackground = false
        focusRingType = .none
        textColor = .clear
        usesSingleLineMode = true
        cell?.isScrollable = true
        contentType = .oneTimeCode
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome, let editor = currentEditor() as? NSTextView {
            // Hide the field editor's caret and selection, the digit boxes
            // underneath are the visible representation
            editor.insertionPointColor = .clear
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor.clear,
                .foregroundColor: NSColor.clear,
            ]
        }
        return didBecome
    }
}

// MARK: - PinCodeCharacterBox

/// Display-only box for a single digit
private class PinCodeCharacterBox: NSTextField {
    var character: Character? = nil {
        didSet {
            stringValue = character.map(String.init) ?? ""
        }
    }

    var isActive: Bool = false {
        didSet {
            layer?.borderWidth = isActive ? 2 : 0
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.cornerRadius = isActive ? 3 : 0
        }
    }

    init() {
        super.init(frame: .zero)

        wantsLayer = true
        isEditable = false
        isSelectable = false
        alignment = .center
        maximumNumberOfLines = 1
        font = .boldSystemFont(ofSize: 48)

        setContentHuggingPriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
