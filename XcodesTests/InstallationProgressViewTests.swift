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

    func testXcodeRowUsesReplacementDownloadProgress() throws {
        func row(completed: Int64) -> some View {
            let progress = Progress(totalUnitCount: 100)
            progress.completedUnitCount = completed
            return InstallationStepRowView(installationStep: .downloading(progress: progress), cancel: {})
                .accentColor(Color(red: 1, green: 0, blue: 0))
                .transaction { $0.animation = nil }
        }

        let hostingView = NSHostingView(rootView: row(completed: 6))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        defer { window.contentView = nil }
        let initialArc = try accentPixelCount(in: hostingView)

        // A resumed download supplies a new Progress while remaining in the downloading stage.
        hostingView.rootView = row(completed: 75)
        let replacementArc = try accentPixelCount(in: hostingView)

        XCTAssertGreaterThan(initialArc, 0)
        XCTAssertGreaterThan(replacementArc, initialArc * 2)
    }

    private func accentPixelCount(in view: NSView) throws -> Int {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        // Count the red arc and stop glyph, ignoring the gray track and transparent background.
        var count = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.alphaComponent > 0.5, color.redComponent - color.greenComponent > 0.35 {
                    count += 1
                }
            }
        }
        return count
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
