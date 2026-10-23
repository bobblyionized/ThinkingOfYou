//  InstagramWebCoordinator.swift
//  ThinkingOfYou/Instagram — owns the WKWebView: configuration (persistent
//  data store, mobile Safari UA, Cage.js at document start in the page world),
//  the JS <-> native bridge, and the WKNavigationDelegate backstop that applies
//  CageRules to full page loads.

import UIKit
import WebKit

@MainActor
final class InstagramWebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let messageHandlerName = "toy"

    let webView: WKWebView
    private(set) weak var model: InstagramViewModel?

    private let contentController: WKUserContentController
    private let cageSource: String?
    private var observations: [NSKeyValueObservation] = []

    init(model: InstagramViewModel) {
        self.model = model

        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile

        self.contentController = contentController
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.cageSource = InstagramWebCoordinator.loadCageSource()
        super.init()

        contentController.add(ScriptMessageProxy(target: self), contentWorld: .page, name: Self.messageHandlerName)
        installUserScripts()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = Self.mobileSafariUserAgent()
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.isInspectable = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground

        observeWebView()
        webView.load(URLRequest(url: CageRules.inboxURL))
    }

    // MARK: Commands (from InstagramViewModel)

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func reload() {
        if webView.url == nil {
            load(CageRules.inboxURL)
        } else {
            webView.reload()
        }
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    /// Sends {unlocked, ownUsername} to the page now, and re-installs the boot
    /// script so the next page load starts with the same state.
    func pushState() {
        installUserScripts()
        let js = "window.__toySetState && window.__toySetState(\(stateJSON()));"
        webView.evaluateJavaScript(js, completionHandler: nil)
        updateNativeScrollLock()
    }

    // MARK: Scripts

    private var isUnlocked: Bool { model?.isUnlocked ?? false }

    private func stateJSON() -> String {
        var state: [String: Any] = ["unlocked": isUnlocked]
        if let ownUsername = model?.ownUsername {
            state["ownUsername"] = ownUsername
        } else {
            state["ownUsername"] = NSNull()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"unlocked\":false}"
        }
        return text
    }

    private func installUserScripts() {
        contentController.removeAllUserScripts()
        let boot = "window.__toyBoot = \(stateJSON());"
        contentController.addUserScript(WKUserScript(source: boot,
                                                     injectionTime: .atDocumentStart,
                                                     forMainFrameOnly: true,
                                                     in: .page))
        if let cageSource {
            contentController.addUserScript(WKUserScript(source: cageSource,
                                                         injectionTime: .atDocumentStart,
                                                         forMainFrameOnly: true,
                                                         in: .page))
        }
    }

    private static func loadCageSource() -> String? {
        guard let url = Bundle.main.url(forResource: "Cage", withExtension: "js") else {
            assertionFailure("Cage.js is missing from the app bundle")
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func mobileSafariUserAgent() -> String {
        let version = UIDevice.current.systemVersion
        let parts = version.split(separator: ".").map(String.init)
        let major = parts.first ?? "17"
        let minor = parts.count > 1 ? parts[1] : "0"
        let osToken = version.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(osToken) like Mac OS X) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/\(major).\(minor) Mobile/15E148 Safari/604.1"
    }

    // MARK: Bridge (page -> native)

    fileprivate func handleScriptMessage(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "blocked":
            // Cage.js has already bounced (or stayed put); just tell the user.
            model?.didBlock(reason: (message["reason"] as? String) ?? "That page")
        case "ownUsername":
            model?.didDetectUsername(message["username"] as? String)
        case "unread":
            if let count = message["count"] as? Int { model?.didUpdateUnread(count) }
        case "toast":
            if let text = message["text"] as? String, !text.isEmpty { model?.showToast(text) }
        case "ready":
            // Make sure the page has the latest state even if it changed mid-load.
            pushState()
            syncFromWebView()
        case "route":
            syncFromWebView()
        default:
            break
        }
    }

    // MARK: Observation

    private func observeWebView() {
        observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
        ]
    }

    /// KVO may call back from any context: hop to the main actor.
    nonisolated private func scheduleSync() {
        Task { @MainActor [weak self] in
            self?.syncFromWebView()
        }
    }

    private func syncFromWebView() {
        model?.webViewDidUpdate(isLoading: webView.isLoading,
                                url: webView.url,
                                canGoBack: webView.canGoBack,
                                progress: webView.estimatedProgress)
        updateNativeScrollLock()
    }

    /// Native half of "no scrolling to the next reel": the page's own scroll
    /// view is frozen on a single-reel page while locked.
    private func updateNativeScrollLock() {
        let path = webView.url.map(CageRules.pathWithSlash) ?? "/"
        let freeze = !isUnlocked && CageRules.reelCode(inPath: path) != nil
        if webView.scrollView.isScrollEnabled == freeze {
            webView.scrollView.isScrollEnabled = !freeze
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let rules = model?.cageRules ?? CageRules()
        // targetFrame == nil means "open in a new window": treat as main frame.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let decision = rules.decide(url: url, currentURL: webView.url, isMainFrame: isMainFrame, unlocked: isUnlocked)

        switch decision {
        case .allow:
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
        case .block(let block):
            decisionHandler(.cancel)
            model?.didBlock(reason: block.reason)
            if block.bouncesToInbox, !(model?.isAtInbox ?? false) || webView.url == nil {
                load(CageRules.inboxURL)
            }
        case .redirect(let target):
            decisionHandler(.cancel)
            load(target)
        case .openExternally(let target):
            decisionHandler(.cancel)
            UIApplication.shared.open(target)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        reportFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func reportFailure(_ error: Error) {
        let nsError = error as NSError
        // Cancelled loads and policy-interrupted loads (our own blocks) are not failures.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 || nsError.code == 204 { return }
        model?.didFailLoading(nsError.localizedDescription)
        syncFromWebView()
    }

    // MARK: WKUIDelegate

    /// target=_blank / window.open: Instagram pages load here (and are caged
    /// by decidePolicyFor); anything else opens in Safari.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if CageRules.isInstagramHost(url.host) {
                webView.load(navigationAction.request)
            } else if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }
}

/// Breaks the WKUserContentController -> handler retain cycle.
@MainActor
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: InstagramWebCoordinator?

    init(target: InstagramWebCoordinator) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handleScriptMessage(message.body)
    }
}
