import SwiftUI
import WebKit

struct FillEntry: Codable {
    let k: String
    let a: String
    let i: Bool
}

struct FillResult: Codable {
    let filled: Int
    let unknown: [String]
    let individual: [String]
}

@MainActor
final class WebController: ObservableObject {
    weak var webView: WKWebView?

    /// Runs autofill.js in the page. Returns nil if the page or script is unavailable.
    func fill(entries: [FillEntry]) async -> FillResult? {
        guard let wv = webView,
              let scriptURL = Bundle.main.url(forResource: "autofill", withExtension: "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8),
              let raw = try? JSONEncoder().encode(entries),
              let json = String(data: raw, encoding: .utf8) else {
            return nil
        }
        let call = script + "\n;window.__jobitFill(" + json + ");"
        return await withCheckedContinuation { (cont: CheckedContinuation<FillResult?, Never>) in
            wv.evaluateJavaScript(call) { value, _ in
                guard let text = value as? String,
                      let bytes = text.data(using: .utf8),
                      let result = try? JSONDecoder().decode(FillResult.self, from: bytes) else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: result)
            }
        }
    }
}

struct CapturedRaw: Codable {
    let title: String
    let company: String
    let location: String
    let url: String
}

extension WebController {
    /// Reads the job on the current page (title, company, location, link) with capture.js.
    func capture() async -> CapturedRaw? {
        guard let wv = webView,
              let scriptURL = Bundle.main.url(forResource: "capture", withExtension: "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            return nil
        }
        let call = script + "\n;window.__jobitCapture();"
        return await withCheckedContinuation { (cont: CheckedContinuation<CapturedRaw?, Never>) in
            wv.evaluateJavaScript(call) { value, _ in
                guard let text = value as? String,
                      let bytes = text.data(using: .utf8),
                      let result = try? JSONDecoder().decode(CapturedRaw.self, from: bytes) else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: result)
            }
        }
    }
}

/// A web view that keeps every application inside the app: new-window links load in the same
/// view, and links that would hand off to another app (universal links, custom schemes) are blocked.
struct WebContainer: UIViewRepresentable {
    let url: URL
    let controller: WebController
    var onLoaded: (() -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        controller.webView = wv
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onLoaded: onLoaded) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onLoaded: (() -> Void)?

        init(onLoaded: (() -> Void)?) {
            self.onLoaded = onLoaded
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoaded?()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
            if ["http", "https", "about", "blob", "data"].contains(scheme) {
                // Raw value 3 means "allow, but do not try to open a matching app".
                decisionHandler(WKNavigationActionPolicy(rawValue: 3) ?? .allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
