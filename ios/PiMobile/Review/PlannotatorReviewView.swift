import Foundation
import SwiftUI
import WebKit

/// Plannotator review uses a real ephemeral WKWebView restricted to the tunnel's exact HTTP loopback origin.
@MainActor
public struct PlannotatorReviewView: UIViewRepresentable {
    private let url: URL

    /// The caller owns the PlannotatorTunnel and must close it on review dismissal.
    public init(url: URL) { self.url = url }

    /// Creates a nonpersistent web session; external navigation, popups, cookies and broad ATS exceptions are not required.
    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.load(url, in: view)
        return view
    }

    /// SwiftUI refreshes do not reload the page or discard unsent review annotations.
    public func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.load(url, in: uiView)
    }

    /// Navigation decisions compare scheme, literal loopback host and explicit ephemeral port.
    public func makeCoordinator() -> Coordinator { Coordinator() }

    /// Dismissal stops web requests; the parent separately closes its owned SSH tunnel.
    public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.generation = UUID()
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    /// Web navigation and content rules deny all origins except this review's local tunnel.
    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        fileprivate var generation = UUID()
        private var origin: URL?
        private var loadedURL: URL?

        fileprivate func load(_ url: URL, in view: WKWebView) {
            guard loadedURL != url else { return }
            generation = UUID()
            let token = generation
            view.stopLoading()
            loadedURL = url
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  components.scheme == "http", components.host == "127.0.0.1",
                  components.user == nil, components.password == nil,
                  let port = components.port, (1...65535).contains(port) else {
                origin = nil
                return
            }
            origin = url
            let rules: [[String: Any]] = [
                ["trigger": ["url-filter": ".*"], "action": ["type": "block"]],
                ["trigger": ["url-filter": "^http://127\\.0\\.0\\.1:\(port)/"],
                 "action": ["type": "ignore-previous-rules"]],
                ["trigger": ["url-filter": "^ws://127\\.0\\.0\\.1:\(port)/"],
                 "action": ["type": "ignore-previous-rules"]]
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: rules),
                  let source = String(data: data, encoding: .utf8) else { return }
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "PiMobile-review-\(port)", encodedContentRuleList: source
            ) { [weak self, weak view] ruleList, error in
                Task { @MainActor in
                    guard let self, let view, self.generation == token,
                          error == nil, let ruleList else { return } // Fail closed: never load without origin rules.
                    view.configuration.userContentController.removeAllContentRuleLists()
                    view.configuration.userContentController.add(ruleList)
                    view.load(URLRequest(url: url))
                    WKContentRuleListStore.default().removeContentRuleList(forIdentifier: "PiMobile-review-\(port)") { _ in }
                }
            }
        }

        /// Remote redirects and iframe navigations cannot leave the exact local origin.
        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(isLocalOrigin(navigationAction.request.url) ? .allow : .cancel)
        }

        /// Response validation also rejects redirects that cross the local origin.
        public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(isLocalOrigin(navigationResponse.response.url) ? .allow : .cancel)
        }

        /// Same-origin user links reuse the current web view; external links never invoke Safari automatically.
        public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                            for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.navigationType == .linkActivated, isLocalOrigin(navigationAction.request.url) {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func isLocalOrigin(_ candidate: URL?) -> Bool {
            guard let origin, let candidate,
                  let components = URLComponents(url: candidate, resolvingAgainstBaseURL: false) else { return false }
            return components.scheme == "http" && components.host == "127.0.0.1" &&
                components.port == origin.port && components.user == nil && components.password == nil
        }
    }
}
