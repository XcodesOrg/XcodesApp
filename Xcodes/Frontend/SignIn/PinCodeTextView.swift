import Cocoa
import SwiftUI

struct PinCodeTextField: NSViewRepresentable {
    typealias NSViewType = PinCodeTextView

    @Binding var code: String
    let numberOfDigits: Int
    let complete: (String) -> Void

    func makeNSView(context: Context) -> NSViewType {
        let view = PinCodeTextView(numberOfDigits: numberOfDigits)
        view.codeDidChange = { c in code = c }
        view.codeDidComplete = { complete($0) }
        return view
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        if nsView.code != code {
            nsView.code = code
        }
    }
}

struct PinCodeTextField_Previews: PreviewProvider {
    struct PreviewContainer: View {
        @State private var code = ""
        var body: some View {
            PinCodeTextField(code: $code, numberOfDigits: 6) {
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

/// A single text field that accepts a verification code.
/// Uses a single NSTextField to enable macOS SMS autofill functionality.
class PinCodeTextView: NSControl, NSTextFieldDelegate {    
    var code: String = "" {
        didSet {
            guard code != oldValue else { return }
            
            // Ensure code only contains digits and is within length limit
            let filteredCode = String(code.filter { $0.isNumber }.prefix(numberOfDigits))
            if filteredCode != code {
                code = filteredCode
                return
            }
            
            if textField.stringValue != code {
                textField.stringValue = code
            }
            
            codeDidChange?(code)
            
            if code.count == numberOfDigits {
                codeDidComplete?(code)
            }
        }
    }
    var codeDidChange: ((String) -> Void)? = nil
    var codeDidComplete: ((String) -> Void)? = nil

    private let numberOfDigits: Int
    private let textField: NSTextField
    
    // MARK: - Initializers
    
    init(numberOfDigits: Int) {
        self.numberOfDigits = numberOfDigits
        self.textField = NSTextField(frame: .zero)
        
        super.init(frame: .zero)
        
        setupTextField()
        setupLayout()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTextField() {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.delegate = self
        textField.alignment = .center
        textField.font = .monospacedDigitSystemFont(ofSize: 32, weight: .medium)
        textField.placeholderString = String(repeating: "•", count: numberOfDigits)
        
        // Enable one-time code autofill
        if #available(macOS 11.0, *) {
            textField.contentType = .oneTimeCode
        }
        
        // Configure for numeric input
        textField.allowsEditingTextAttributes = false
        
        // Add letter spacing for better readability
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 0
        formatter.maximum = NSNumber(value: Int(String(repeating: "9", count: numberOfDigits))!)
        
        addSubview(textField)
    }
    
    private func setupLayout() {
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(numberOfDigits * 30 + 40)),
            textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }
    
    // MARK: NSTextFieldDelegate
    
    func controlTextDidChange(_ obj: Notification) {
        guard
            let field = obj.object as? NSTextField,
            field === textField,
            isEnabled
        else { return }
        
        let newText = field.stringValue
        
        // Filter to only digits
        let filteredText = String(newText.filter { $0.isNumber }.prefix(numberOfDigits))
        
        if filteredText != newText {
            field.stringValue = filteredText
        }
        
        code = filteredText
    }
    
    // MARK: NSResponder
    
    override var acceptsFirstResponder: Bool {
        true
    }
    
    override func becomeFirstResponder() -> Bool {
        textField.becomeFirstResponder()
    }
}
