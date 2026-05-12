import SwiftUI
import AppKit

/// You probably want ProgressView unless you need more of NSProgressIndicator's API, which this exposes.
struct ProgressIndicator: NSViewRepresentable {
    typealias NSViewType = NSProgressIndicator
    
    let minValue: Double
    let maxValue: Double
    let doubleValue: Double
    let controlSize: NSControl.ControlSize
    let isIndeterminate: Bool
    let style: NSProgressIndicator.Style
    
    func makeNSView(context: Context) -> NSViewType {
        NSProgressIndicator()
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {
        nsView.minValue = minValue
        nsView.maxValue = maxValue
        nsView.doubleValue = doubleValue
        nsView.controlSize = controlSize
        nsView.isIndeterminate = isIndeterminate
        nsView.usesThreadedAnimation = true
        
        nsView.style = style
        nsView.startAnimation(nil)
    }
}

struct ProgressIndicator_Previews: PreviewProvider {
    static var previews: some View {
        ProgressIndicator(
            minValue: 0,
            maxValue: 1,
            doubleValue: 0.4,
            controlSize: .small,
            isIndeterminate: false,
            style: .spinning
        )
    }
}
