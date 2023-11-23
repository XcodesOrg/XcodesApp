//
//  ReleaseDateView.swift
//  Xcodes
//
//  Created by Duong Thai on 11/10/2023.
//  Copyright © 2023 Robots and Pencils. All rights reserved.
//

import SwiftUI

struct ReleaseDateView: View {
    let date: Date?

    var body: some View {
        if let date = date {
            VStack(alignment: .leading) {
                Text("ReleaseDate")
                    .font(.headline)
                Text("\(date, style: .date)")
                    .font(.subheadline)
            }
        } else {
            EmptyView()
        }
    }

    init(date: Date? = nil) {
        self.date = date
    }
}

#Preview {
  ReleaseDateView(date: Date())
    .padding()
}
