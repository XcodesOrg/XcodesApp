//
//  SignInSecurityKeyPin.swift
//  Xcodes
//
//  Created by Kino on 2024-09-26.
//  Copyright © 2024 Robots and Pencils. All rights reserved.
//

import SwiftUI
import AppleAPI

struct SignInSecurityKeyPinView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var pin: String = ""
    let authOptions: AuthOptionsResponse
    let sessionData: AppleSessionData
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(localizeString("SecurityKeyPinDescription"))
                .fixedSize(horizontal: true, vertical: false)
            
            HStack {
                Spacer()
                SecureField("PIN", text: $pin)
                Spacer()
            }
            .padding()
            
            HStack {
                Button("Cancel", action: { isPresented = false })
                    .keyboardShortcut(.cancelAction)
                Spacer()
                ProgressButton(isInProgress: appState.isProcessingAuthRequest,
                               action: submitPinCode) {
                    Text("Continue")
                }
                .keyboardShortcut(.defaultAction)
                // FIDO2 device pin codes must be at least 4 code points
                // https://docs.yubico.com/yesdk/users-manual/application-fido2/fido2-pin.html
                .disabled(pin.count < 4)
            }
            .frame(height: 25)
        }
        .padding()
        .emittingError($appState.authError, recoveryHandler: { _ in })
    }
    
    func submitPinCode() {
        appState.createAndSubmitSecurityKeyAssertationWithPinCode(pin, sessionData: sessionData, authOptions: authOptions)
    }
}

#Preview {
    SignInSecurityKeyPinView(isPresented: .constant(true),
                             authOptions: AuthOptionsResponse(
                                trustedPhoneNumbers: nil,
                                trustedDevices: nil,
                                securityCode: .init(length: 6)
                             ), sessionData: AppleSessionData(serviceKey: "", sessionID: "", scnt: ""))
    .environmentObject(AppState())
}
