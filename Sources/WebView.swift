//
//  WebView.swift
//
import UIKit
import WebKit
import SwiftUI
import UserNotifications

struct WebContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        if #available(iOS 13.0, *) {
            config.defaultWebpagePreferences.preferredContentMode = .desktop // 🖥️ sitio de escritorio
        }
        config.allowsInlineMediaPlayback = true
        if #available(iOS 14.0, *) {
            config.allowsPictureInPictureMediaPlayback = true
        }
        if #available(iOS 10.0, *) { config.mediaTypesRequiringUserActionForPlayback = [] }
        config.websiteDataStore = .default()

        let webView = TeamsWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.load(URLRequest(url: URL(string: "https://teams.microsoft.com")!))
        return container
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

final class TeamsWebView: WKWebView, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)

        navigationDelegate = self
        uiDelegate = self
        scrollView.bounces = true
        scrollView.alwaysBounceVertical = true
        allowsBackForwardNavigationGestures = true
        allowsLinkPreview = true

        // Inyección JS para puente de notificaciones + cambios de título
        let js = Self.notificationBridgeJS
        let userScript = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(userScript)
        configuration.userContentController.add(self, name: "teamsNotify")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "teamsNotify" else { return }
        if let dict = message.body as? [String: Any] {
            let type = (dict["type"] as? String) ?? ""
            switch type {
            case "notification":
                let title = (dict["title"] as? String) ?? "Teams"
                let body  = (dict["body"] as? String)  ?? ""
                Self.fireLocalNotification(title: title, body: body)
            case "title":
                if let t = dict["value"] as? String, Self.shouldNotifyFromTitle(t) {
                    Self.fireLocalNotification(title: "Teams", body: t)
                }
            default: break
            }
        }
    }

    private static func fireLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body.isEmpty ? "Actividad en Teams" : body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private static func shouldNotifyFromTitle(_ t: String) -> Bool {
        let lowered = t.lowercased()
        return t.range(of: #"^\s*\(\d+\)"#, options: .regularExpression) != nil
            || lowered.contains("new message")
            || lowered.contains("mensaje nuevo")
            || lowered.contains("call")
            || lowered.contains("llamada")
            || lowered.contains("meeting")
            || lowered.contains("reunión")
    }

    // MARK: - Navegación
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        if let url = navigationAction.request.url {
            if let scheme = url.scheme?.lowercased(), !scheme.hasPrefix("http") {
                // Bloquear intentos de abrir app nativa msteams://
                if scheme.contains("msteams") {
                    decisionHandler(.cancel); return
                }
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel); return
            }
        }

        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // JS alert/confirm/prompt
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        presentAlert(title: nil, message: message, actions: [UIAlertAction(title: "OK", style: .default, handler: { _ in completionHandler() })])
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        presentAlert(title: nil, message: message, actions: [
            UIAlertAction(title: "Cancelar", style: .cancel, handler: { _ in completionHandler(false) }),
            UIAlertAction(title: "OK", style: .default, handler: { _ in completionHandler(true) })
        ])
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel, handler: { _ in completionHandler(nil) }))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completionHandler(alert.textFields?.first?.text) }))
        topMostController()?.present(alert, animated: true, completion: nil)
    }

    private func presentAlert(title: String?, message: String?, actions: [UIAlertAction]) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        actions.forEach { alert.addAction($0) }
        topMostController()?.present(alert, animated: true, completion: nil)
    }

    private func topMostController() -> UIViewController? {
        var keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        if keyWindow == nil {
            keyWindow = UIApplication.shared.windows.first { $0.isKeyWindow }
        }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - JS puente
    private static let notificationBridgeJS = """
    (function() {
      const NATIVE = (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.teamsNotify) ? window.webkit.messageHandlers.teamsNotify : null;
      try {
        const target = document.querySelector('title') || document.head;
        const obs = new MutationObserver(() => {
          try { const t = document.title || ''; NATIVE && NATIVE.postMessage({ type: 'title', value: t }); } catch(e) {}
        });
        obs.observe(target, { subtree: true, characterData: true, childList: true });
      } catch (e) {}
      try {
        if (window.Notification) {
          const _N = window.Notification;
          const wrapper = function(title, opts) {
            try { NATIVE && NATIVE.postMessage({ type: 'notification', title: String(title || 'Teams'), body: (opts && opts.body) || '' }); } catch(e) {}
            try { return new _N(title, opts); } catch(e) { return undefined; }
          };
          wrapper.requestPermission = function(cb) { try { cb && cb('granted'); } catch(e) {}; return Promise.resolve('granted'); };
          wrapper.permission = 'granted';
          window.Notification = wrapper;
        }
      } catch (e) {}
    })();
    """
}
