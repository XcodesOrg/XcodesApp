import AppKit
import SwiftUI

/// Native three-state checkbox for selecting some or all eligible category items.
struct CleanupSelectionCheckbox: NSViewRepresentable {
    let state: NSControl.StateValue
    let enabled: Bool
    let label: String
    let toggle: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.toggle))
        button.allowsMixedState = true
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = toggle
        button.state = state
        button.isEnabled = enabled
        button.setAccessibilityLabel(label)
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: toggle) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func toggle() { action() }
    }
}
