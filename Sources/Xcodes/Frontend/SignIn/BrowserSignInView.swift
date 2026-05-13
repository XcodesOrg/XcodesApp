import SwiftUI
import WebKit

struct BrowserSignInView: View {
    @Bindable var authenticationStore: AuthenticationStore
    let cancel: () -> Void
    let usePasswordSignIn: () -> Void

    @State private var cookieStore: WKHTTPCookieStore?
    @State private var currentURL: URL?
    @State private var isLoading = false

    private let initialURL = URL(string: "https://appstoreconnect.apple.com/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            AppleSignInWebView(
                initialURL: initialURL,
                onCookieStoreReady: { cookieStore = $0 },
                onNavigationFinished: { currentURL = $0 },
                currentURL: $currentURL,
                isLoading: $isLoading
            )
            .frame(minWidth: 760, minHeight: 520)

            if let authError = authenticationStore.authError {
                Text(authError.legibleLocalizedDescription)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.red)
            }

            footer
        }
        .padding()
    }

    private var header: some View {
        HStack {
            Text("Sign in with Apple")
                .font(.headline)
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(currentURL?.host ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Use Password") {
                authenticationStore.authError = nil
                usePasswordSignIn()
            }
            Button("Cancel") {
                authenticationStore.authError = nil
                cancel()
            }
            .keyboardShortcut(.cancelAction)
            ProgressButton(
                isInProgress: authenticationStore.isProcessingAuthRequest,
                action: { finishBrowserSignIn() },
                label: {
                    Text("Continue")
                }
            )
            .keyboardShortcut(.defaultAction)
            .disabled(cookieStore == nil)
        }
        .frame(height: 25)
    }

    private func finishBrowserSignIn() {
        Task {
            guard let cookieStore else { return }

            let cookies = await cookieStore.allCookies()
            do {
                _ = try await authenticationStore.signInWithBrowser(cookies: cookies)
                cancel()
            } catch {
                // AuthenticationStore publishes the error for the sheet.
            }
        }
    }
}

struct BrowserSignInView_Previews: PreviewProvider {
    static var previews: some View {
        BrowserSignInView(
            authenticationStore: AuthenticationStore(),
            cancel: {},
            usePasswordSignIn: {}
        )
    }
}
