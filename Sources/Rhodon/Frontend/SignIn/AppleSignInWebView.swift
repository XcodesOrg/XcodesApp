import SwiftUI
import WebKit

struct AppleSignInWebView: NSViewRepresentable {
    let initialURL: URL
    let onCookieStoreReady: (WKHTTPCookieStore) -> Void
    let onNavigationFinished: (URL) -> Void
    @Binding var currentURL: URL?
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentURL: $currentURL,
            isLoading: $isLoading,
            onNavigationFinished: onNavigationFinished
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        onCookieStoreReady(configuration.websiteDataStore.httpCookieStore)
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateNSView(_: WKWebView, context _: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var currentURL: Binding<URL?>
        private var isLoading: Binding<Bool>
        private let onNavigationFinished: (URL) -> Void

        init(
            currentURL: Binding<URL?>,
            isLoading: Binding<Bool>,
            onNavigationFinished: @escaping (URL) -> Void
        ) {
            self.currentURL = currentURL
            self.isLoading = isLoading
            self.onNavigationFinished = onNavigationFinished
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            currentURL.wrappedValue = webView.url
            isLoading.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
            currentURL.wrappedValue = webView.url
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            currentURL.wrappedValue = webView.url
            isLoading.wrappedValue = false

            if let url = webView.url {
                onNavigationFinished(url)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail _: WKNavigation!,
            withError _: Error
        ) {
            currentURL.wrappedValue = webView.url
            isLoading.wrappedValue = false
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation _: WKNavigation!,
            withError _: Error
        ) {
            currentURL.wrappedValue = webView.url
            isLoading.wrappedValue = false
        }
    }
}

extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}
