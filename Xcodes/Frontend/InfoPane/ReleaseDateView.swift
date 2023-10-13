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

struct ReleaseDateView_Preview: PreviewProvider {
    static var previews: some View {
        WrapperView()
    }
}

private struct WrapperView: View {
    @State var isNil = false
    var date: Date? { isNil ? nil : Date() }

    var body: some View {
        VStack {
            ReleaseDateView(date: date)
                .border(.red)
            Spacer()
            Toggle(isOn: $isNil) {
                Text("Is Nil?")
            }
        }
        .frame(width: 300, height: 100)
        .padding()
    }
}
