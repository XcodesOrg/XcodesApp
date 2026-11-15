//
//  NavigationSplitViewWrapper.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2023-12-12.
//

import AppKit
import SwiftUI

private enum NavigationSplitViewLayout {
    static let sidebarMinimumWidth: CGFloat = 380
    static let sidebarIdealWidth: CGFloat = 440
    static let sidebarMaximumWidth: CGFloat = 700
    static let dividerWidth: CGFloat = 1
    static let sidebarRestoreMargin: CGFloat = 24
}

struct NavigationSplitViewWrapper<Sidebar, Detail>: View where Sidebar: View, Detail: View {
    private let sidebar: Sidebar
    private let detail: Detail
    private let detailMinimumWidth: CGFloat
    @Binding private var columnVisibility: NavigationSplitViewVisibility
    @State private var automaticallyCollapsedSidebar = false
    @State private var windowReference = SplitViewWindowReference()
    
    init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        detailMinimumWidth: CGFloat,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self._columnVisibility = columnVisibility
        self.detailMinimumWidth = detailMinimumWidth
        self.sidebar = sidebar()
        self.detail = detail()
    }
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let availableSidebarWidth = width - detailMinimumWidth - NavigationSplitViewLayout.dividerWidth
            let maximumSidebarWidth = max(
                NavigationSplitViewLayout.sidebarMinimumWidth,
                min(NavigationSplitViewLayout.sidebarMaximumWidth, availableSidebarWidth)
            )
            NavigationSplitView(columnVisibility: visibility(forWidth: width)) {
                sidebar
                    .navigationSplitViewColumnWidth(
                        min: NavigationSplitViewLayout.sidebarMinimumWidth,
                        ideal: min(NavigationSplitViewLayout.sidebarIdealWidth, maximumSidebarWidth),
                        max: maximumSidebarWidth
                    )
            } detail: {
                detail
            }
            .navigationSplitViewStyle(.balanced)
            .onChange(of: width, initial: true) { updateVisibility(forWidth: width) }
            .onChange(of: detailMinimumWidth) { updateVisibility(forWidth: width) }
            .onChange(of: columnVisibility) { previous, visibility in
                guard visibility != .detailOnly else { return }
                automaticallyCollapsedSidebar = false
                if previous == .detailOnly {
                    // Tiled windows need an explicit resize when reopening the sidebar.
                    windowReference.ensureContentWidth(minimumWidthWithSidebar)
                }
            }
        }
        .frame(minWidth: detailMinimumWidth)
        .background(SplitViewWindowReader(reference: windowReference))
    }

    private var minimumWidthWithSidebar: CGFloat {
        NavigationSplitViewLayout.sidebarMinimumWidth + detailMinimumWidth + NavigationSplitViewLayout.dividerWidth
    }

    private func visibility(forWidth width: CGFloat) -> Binding<NavigationSplitViewVisibility> {
        Binding {
            columnVisibility
        } set: { visibility in
            guard visibility != columnVisibility else { return }
            // Native collapse notifications can precede the geometry update.
            automaticallyCollapsedSidebar = visibility == .detailOnly && width < minimumWidthWithSidebar
            columnVisibility = visibility
        }
    }

    private func updateVisibility(forWidth width: CGFloat) {
        guard width > 0 else { return }
        if width < minimumWidthWithSidebar, columnVisibility != .detailOnly {
            automaticallyCollapsedSidebar = true
            columnVisibility = .detailOnly
        } else if automaticallyCollapsedSidebar,
                  width >= minimumWidthWithSidebar + NavigationSplitViewLayout.sidebarRestoreMargin {
            automaticallyCollapsedSidebar = false
            columnVisibility = .all
        }
    }
}

@MainActor
private final class SplitViewWindowReference {
    weak var window: NSWindow?

    func ensureContentWidth(_ minimumWidth: CGFloat) {
        guard let window else { return }
        let contentSize = window.contentRect(forFrameRect: window.frame).size
        guard contentSize.width < minimumWidth else { return }
        window.setContentSize(NSSize(width: minimumWidth, height: contentSize.height))
        if let screen = window.screen, window.frame.maxX > screen.visibleFrame.maxX {
            window.setFrameOrigin(NSPoint(
                x: max(screen.visibleFrame.minX, screen.visibleFrame.maxX - window.frame.width),
                y: window.frame.minY
            ))
        }
    }
}

private struct SplitViewWindowReader: NSViewRepresentable {
    let reference: SplitViewWindowReference

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.reference = reference
        return view
    }

    func updateNSView(_ view: WindowView, context: Context) {
        view.reference = reference
        reference.window = view.window
    }

    final class WindowView: NSView {
        var reference: SplitViewWindowReference?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reference?.window = window
        }
    }
}
