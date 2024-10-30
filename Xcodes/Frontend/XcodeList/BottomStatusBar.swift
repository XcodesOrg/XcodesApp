//
//  BottomStatusBar.swift
//  Xcodes
//
//  Created by Matt Kiazyk on 2022-06-03.
//  Copyright © 2022 Robots and Pencils. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import WebKit

struct BottomStatusModifier: ViewModifier {
    @EnvironmentObject var appState: AppState
    @AppStorage(PreferenceKey.hideSupportXcodes.rawValue) var hideSupportXcodes = false

    @SwiftUI.Environment(\.openURL) var openURL: OpenURLAction
    
    @State var showWebLogin: Bool = false
    @State var openProgress = false
    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Text(appState.bottomStatusBarMessage)
                            .font(.subheadline)
                    Spacer()
                    if !hideSupportXcodes {
                        Button(action: {
                            openURL(URL(string: "https://opencollective.com/xcodesapp")!)
                        }) {
                            HStack {
                                Image(systemName: "heart.circle")
                                Text("Support.Xcodes")
                            }
                        }
                    }
                    Text("\(Bundle.main.shortVersion!) (\(Bundle.main.version!))")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: 30, alignment: .leading)
                .padding([.leading, .trailing], 10)
            }
            .frame(maxWidth: .infinity, maxHeight: 30, alignment: .leading)
        }
        .sheet(isPresented: $showWebLogin) {
            VStack(spacing: 0) {
                                          AppleWebLoginView { token in
                                              populateOlympus(token: token)
                                          }
                                          Divider().padding(.horizontal, -16)
                                          HStack {
                                              Text("Please sign in to Apple in this page.")
                                              Spacer()
                                              Button("Cancel") {
                                                  showWebLogin = false
                                              }
                                          }
                                          .padding(8)
                                      }
                                      .frame(width: 800, height: 500)
        }
        
    }
    
    func populateOlympus(token: String) {
        showWebLogin = false
            openProgress = true
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                
                appState.updateACToken(token)
                
//                var request = URLRequest(url: URL(string: "https://appstoreconnect.apple.com/olympus/v1/session")!)
//                request.setValue("myacinfo=\(token);", forHTTPHeaderField: "Cookie")
//                URLSession.shared.dataTask(with: request) { data, _, _ in
//                    guard let data else { return }
//                    guard let dic = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
//                    guard let userData = dic["user"] as? [String: Any] else { return }
//                    guard let userDataRaw = try? JSONSerialization.data(withJSONObject: userData) else { return }
//                    //guard let user = try? JSONDecoder().decode(User.self, from: userDataRaw) else { return }
//
//                    DispatchQueue.main.async {
//                        openProgress = false
//                    }
////                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
////                        self.user = user
////                    }
//                }.resume()
            }
        }
}

extension View {
    func bottomStatusBar() -> some View {
        self.modifier(
            BottomStatusModifier()
        )
    }
}

struct Previews_BottomStatusBar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HStack {

            }
            .bottomStatusBar()
            .environmentObject({ () -> AppState in
                let a = AppState()
                return a }()
            )
            .defaultAppStorage({ () -> UserDefaults in
                let d = UserDefaults(suiteName: "hide_support")!
                d.set(true, forKey: PreferenceKey.hideSupportXcodes.rawValue)
                return d
            }())

            HStack {

            }
            .bottomStatusBar()
            .environmentObject({ () -> AppState in
                let a = AppState()
                return a }()
            )
            .defaultAppStorage({ () -> UserDefaults in
                let d = UserDefaults(suiteName: "show_support")!
                d.set(false, forKey: PreferenceKey.hideSupportXcodes.rawValue)
                return d
            }())
        }
    }
}

public struct AppleWebLoginView: View {
    let onCredentialUpdate: (String) -> Void

    public init(onCredentialUpdate: @escaping (String) -> Void) {
        self.onCredentialUpdate = onCredentialUpdate
    }

    @State var showProgressOverlay = true

    public var body: some View {
        AppleWebLoginUI {
            showProgressOverlay = false
        } onCredentialUpdate: { credential in
            onCredentialUpdate(credential)
        }
        .overlay(loadingIndicator)
    }

    @ViewBuilder
    var loadingIndicator: some View {
        if showProgressOverlay {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .padding()
        }
    }
}
public struct AppleWebLoginUI: NSViewRepresentable {
    let onFirstLoadComplete: () -> Void
    let onCredentialUpdate: (String) -> Void

    public init(
        onFirstLoadComplete: @escaping () -> Void,
        onCredentialUpdate: @escaping (String) -> Void
    ) {
        self.onFirstLoadComplete = onFirstLoadComplete
        self.onCredentialUpdate = onCredentialUpdate
    }

    public func makeCoordinator() -> CoordinateCore {
        .init()
    }

    public func makeNSView(context: Context) -> NSView {
        context.coordinator.core.installFirstLoadCompleteTrap(onFirstLoadComplete)
        context.coordinator.core.installCredentialPopulationTrap(onCredentialUpdate)
        return context.coordinator.core.webView
    }

    public func updateNSView(_: NSView, context _: Context) {}
}
public extension AppleWebLoginUI {
    class CoordinateCore {
        public let core = AppleWebLoginCore()

        public init() {}
    }
}
private let loginURL = URL(string: "https://developer.apple.com/services-account/download?path=/Developer_Tools/Xcode_16.2_beta_1/Xcode_16.2_beta_1.xip")!

public class AppleWebLoginCore: NSObject, WKUIDelegate, WKNavigationDelegate {
    var webView: WKWebView {
        associatedWebView
    }

    private let associatedWebView: WKWebView
    private var dataPopulationTimer: Timer? = nil
    private var firstLoadComplete = false

    public private(set) var onFirstLoadComplete: (() -> Void)?
    public private(set) var onCredentialPopulation: ((String) -> Void)?

    override public init() {
        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController = contentController
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.websiteDataStore = .nonPersistent()

        associatedWebView = .init(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            configuration: configuration
        )
        associatedWebView.isHidden = true

        super.init()

        associatedWebView.uiDelegate = self
        associatedWebView.navigationDelegate = self

        associatedWebView.load(.init(url: loginURL))

        #if DEBUG
            if associatedWebView.responds(to: Selector(("setInspectable:"))) {
                associatedWebView.perform(Selector(("setInspectable:")), with: true)
            }
        #endif

        let dataPopulationTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            removeUnwantedElements()
            populateData()
        }
        RunLoop.main.add(dataPopulationTimer, forMode: .common)
        self.dataPopulationTimer = dataPopulationTimer
    }

    deinit {
        dataPopulationTimer?.invalidate()
        onCredentialPopulation = nil
    }

    public func webView(_: WKWebView, didFinish _: WKNavigation!) {
        guard !firstLoadComplete else { return }
        defer { firstLoadComplete = true }
        associatedWebView.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.onFirstLoadComplete?()
            self.onFirstLoadComplete = nil
        }
    }

    public func installFirstLoadCompleteTrap(_ block: @escaping () -> Void) {
        onFirstLoadComplete = block
    }

    public func installCredentialPopulationTrap(_ block: @escaping (String) -> Void) {
        onCredentialPopulation = block
    }

    private func removeUnwantedElements() {
        let removeElements = """
        Element.prototype.remove = function() {
            this.parentElement.removeChild(this);
        }
        NodeList.prototype.remove = HTMLCollection.prototype.remove = function() {
            for(var i = this.length - 1; i >= 0; i--) {
                if(this[i] && this[i].parentElement) {
                    this[i].parentElement.removeChild(this[i]);
                }
            }
        }
        document.getElementById("globalheader").remove();
        document.getElementById("ac-localnav").remove();
        document.getElementById("ac-globalfooter").remove();
        document.getElementsByClassName('landing__animation').remove();
        """
        associatedWebView.evaluateJavaScript(removeElements) { _, _ in
        }
    }

    private func populateData() {
        guard let onCredentialPopulation else { return }
        associatedWebView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies where cookie.name == "myacinfo" {
                let value = cookie.value
                onCredentialPopulation(value)
                self.onCredentialPopulation = nil
            }
        }
    }
}
