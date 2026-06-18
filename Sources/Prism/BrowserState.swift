import SwiftUI
import WebKit
import Combine

/// One browser tab. Holds its own WKWebView so each tab keeps history/state.
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var title: String = "New Tab"
    @Published var urlString: String = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress: Double = 0

    let webView: WKWebView

    init() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: config)
    }
}

/// Owns the set of tabs and exposes navigation intents the UI (and the AI agent)
/// can call. This is the single source of truth for browsing.
final class BrowserState: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var selectedTabID: UUID?

    private var observers: [NSKeyValueObservation] = []

    init() {
        newTab(url: "https://www.apple.com")
    }

    var selectedTab: Tab? {
        tabs.first { $0.id == selectedTabID }
    }

    // MARK: - Tab lifecycle

    func newTab(url: String? = nil) {
        let tab = Tab()
        bind(tab)
        tabs.append(tab)
        selectedTabID = tab.id
        if let url { load(url, in: tab) }
    }

    func closeTab(_ tab: Tab) {
        if let idx = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs.remove(at: idx)
            if selectedTabID == tab.id {
                selectedTabID = tabs.last?.id
            }
        }
        if tabs.isEmpty { newTab(url: "https://www.apple.com") }
    }

    func select(_ tab: Tab) { selectedTabID = tab.id }

    // MARK: - Navigation intents (also used by the agent)

    /// Normalizes user input into a URL or a web search and loads it.
    func go(to input: String, in tab: Tab? = nil) {
        guard let tab = tab ?? selectedTab else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let looksLikeURL = trimmed.contains(".") && !trimmed.contains(" ")
        let target: String
        if looksLikeURL {
            target = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
        } else {
            let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            target = "https://duckduckgo.com/?q=\(q)"
        }
        load(target, in: tab)
    }

    func load(_ urlString: String, in tab: Tab) {
        guard let url = URL(string: urlString) else { return }
        tab.urlString = urlString
        tab.webView.load(URLRequest(url: url))
    }

    func reload()   { selectedTab?.webView.reload() }
    func goBack()   { selectedTab?.webView.goBack() }
    func goForward(){ selectedTab?.webView.goForward() }

    /// Returns the rendered text of the current page (used by the agent's "read page" tool).
    func readCurrentPageText() async -> String {
        guard let tab = selectedTab else { return "" }
        let js = "document.body.innerText"
        return await withCheckedContinuation { cont in
            tab.webView.evaluateJavaScript(js) { result, _ in
                cont.resume(returning: (result as? String) ?? "")
            }
        }
    }

    // MARK: - KVO binding so SwiftUI reflects WebKit state

    private func bind(_ tab: Tab) {
        observers.append(tab.webView.observe(\.title, options: [.new]) { wv, _ in
            DispatchQueue.main.async { tab.title = wv.title?.isEmpty == false ? wv.title! : "New Tab" }
        })
        observers.append(tab.webView.observe(\.url, options: [.new]) { wv, _ in
            DispatchQueue.main.async { if let u = wv.url?.absoluteString { tab.urlString = u } }
        })
        observers.append(tab.webView.observe(\.canGoBack, options: [.new]) { wv, _ in
            DispatchQueue.main.async { tab.canGoBack = wv.canGoBack }
        })
        observers.append(tab.webView.observe(\.canGoForward, options: [.new]) { wv, _ in
            DispatchQueue.main.async { tab.canGoForward = wv.canGoForward }
        })
        observers.append(tab.webView.observe(\.isLoading, options: [.new]) { wv, _ in
            DispatchQueue.main.async { tab.isLoading = wv.isLoading }
        })
        observers.append(tab.webView.observe(\.estimatedProgress, options: [.new]) { wv, _ in
            DispatchQueue.main.async { tab.progress = wv.estimatedProgress }
        })
    }
}
