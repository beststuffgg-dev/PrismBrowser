import SwiftUI
import WebKit

/// Bridges a tab's WKWebView into SwiftUI. Because each Tab owns its WKWebView,
/// switching tabs just swaps which view is shown.
struct WebView: NSViewRepresentable {
    let tab: Tab

    func makeNSView(context: Context) -> WKWebView {
        tab.webView.setValue(false, forKey: "drawsBackground") // let our dark theme show through
        return tab.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // WebKit drives its own content; nothing to push here.
    }
}
