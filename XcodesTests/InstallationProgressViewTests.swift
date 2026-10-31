import Cocoa
import SwiftUI
import XCTest

@testable import Xcodes

@MainActor
final class InstallationProgressViewTests: XCTestCase {
    func testXcodeDetailUsesReplacementDownloadProgress() {
        assertUsesReplacementProgress { progress in
            InstallationStepDetailView(installationStep: .downloading(progress: progress))
        }
    }

    func testXcodeRowUsesReplacementDownloadProgress() {
        assertUsesReplacementProgress { progress in
            InstallationStepRowView(
                installationStep: .downloading(progress: progress),
                highlighted: false,
                cancel: {}
            )
        }
    }

    func testRuntimeDetailUsesReplacementDownloadProgress() {
        assertUsesReplacementProgress { progress in
            RuntimeInstallationStepDetailView(installationStep: .downloading(progress: progress))
        }
    }

    private func assertUsesReplacementProgress<Content: View>(
        @ViewBuilder content: (Progress) -> Content,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let original = Progress(totalUnitCount: 100)
        original.completedUnitCount = 6
        let hostingView = NSHostingView(rootView: content(original))
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 180)
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertEqual(progressIndicator(in: hostingView)?.doubleValue, 0.06, file: file, line: line)

        // A resumed download supplies a new Progress while remaining in the downloading stage.
        let replacement = Progress(totalUnitCount: 100)
        replacement.completedUnitCount = 75
        hostingView.rootView = content(replacement)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(progressIndicator(in: hostingView)?.doubleValue, 0.75, file: file, line: line)
    }

    private func progressIndicator(in view: NSView) -> NSProgressIndicator? {
        if let indicator = view as? NSProgressIndicator {
            return indicator
        }
        return view.subviews.lazy.compactMap { self.progressIndicator(in: $0) }.first
    }
}
