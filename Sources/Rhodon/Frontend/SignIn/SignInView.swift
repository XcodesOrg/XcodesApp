import AppleAPI
import SwiftUI

struct SignInView: View {
    enum Method {
        case browser
        case password
    }

    @Bindable var authenticationStore: AuthenticationStore
    let cancel: () -> Void
    @State private var method: Method = .browser

    var body: some View {
        if authenticationStore.authenticationState == .authenticated {
            signedInView
        } else {
            switch method {
            case .browser:
                BrowserSignInView(
                    authenticationStore: authenticationStore,
                    cancel: cancel,
                    usePasswordSignIn: { method = .password }
                )
            case .password:
                VStack(alignment: .leading, spacing: 0) {
                    SignInCredentialsView(authenticationStore: authenticationStore, cancel: cancel)
                    Divider()
                    HStack {
                        Spacer()
                        Button("Use Browser") {
                            authenticationStore.authError = nil
                            method = .browser
                        }
                    }
                    .padding()
                }
                .frame(width: 400)
            }
        }
    }

    private var signedInView: some View {
        VStack {
            SignedInView(authenticationStore: authenticationStore)
                .padding(32)
            HStack {
                Spacer()
                Button("Close") { cancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
    }
}

struct SignInView_Previews: PreviewProvider {
    static var previews: some View {
        SignInView(authenticationStore: AuthenticationStore(), cancel: {})
            .previewLayout(.sizeThatFits)
    }
}
