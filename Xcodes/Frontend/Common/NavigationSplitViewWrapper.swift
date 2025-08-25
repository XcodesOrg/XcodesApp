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
        NavigationSplitView {
            if #available(macOS 14, *) {
                sidebar
                    .navigationSplitViewColumnWidth(min: 290, ideal: 290)
            } else {
                sidebar
            }
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
    }
}
