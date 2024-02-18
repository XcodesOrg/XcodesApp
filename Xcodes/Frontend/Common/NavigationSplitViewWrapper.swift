//
//  NavigationSplitViewWrapper.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2023-12-12.
//

import SwiftUI

struct NavigationSplitViewWrapper<Sidebar, Detail>: View where Sidebar: View, Detail: View {
    private var sidebar: Sidebar
    private var detail: Detail
    
    init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail:  () -> Detail
    ) {
        self.sidebar = sidebar()
        self.detail = detail()
    }
    
    var body: some View {
        if #available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *) {
            // Use the latest API available
            NavigationSplitView {
                
                if #available(macOS 14, *) {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 250, ideal: 300)
                } else {
                    sidebar
                }
            } detail: {
                detail
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            // Alternative code for earlier versions of OS.
            NavigationView {
                // The first column is the sidebar.
                sidebar
                    .frame(minWidth: 250)
                detail
            }
            .navigationViewStyle(.columns)
        }
    }
}
