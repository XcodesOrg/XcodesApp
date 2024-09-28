//
//  SignInSecurityKeyPin.swift
//  Xcodes
//
//  Created by Kino on 2024-09-26.
//  Copyright © 2024 Robots and Pencils. All rights reserved.
//

import SwiftUI
import AppleAPI

struct SignInSecurityKeyTouchView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .center) {
            Image(systemName: "key.radiowaves.forward")
                .font(.system(size: 32)).bold()
                .padding(.bottom)
            HStack {
                Spacer()
                Text(localizeString("SecurityKeyTouchDescription"))
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
            }
            HStack {
                Button("Cancel", action: self.cancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(x: 0.5, y: 0.5, anchor: .center)
                    .isHidden(!appState.isProcessingAuthRequest)
                
                .keyboardShortcut(.defaultAction)
            }
            .frame(height: 25)
        }
        .padding()
        .emittingError($appState.authError, recoveryHandler: { _ in })
    }
    
    func cancel() {
        appState.cancelSecurityKeyAssertationRequest()
        isPresented = false
    }
}

#Preview {
    SignInSecurityKeyTouchView(isPresented: .constant(true))
    .environmentObject(AppState())
}
