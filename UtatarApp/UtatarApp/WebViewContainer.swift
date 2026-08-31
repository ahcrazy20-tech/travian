import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: WebViewModel
    @ObservedObject var spyBot: SpyAttackBot
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        // Add user script for page monitoring
        let script = WKUserScript(source: pageMonitorJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: "gameObserver")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.isScrollEnabled = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        
        // Set custom user agent
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Mobile/15E148 Safari/604.1"
        
        viewModel.setupWebView(webView)
        spyBot.setup(webView: webView)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Updates handled by ViewModel
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    // JavaScript to monitor game events
    var pageMonitorJS: String {
        return """
        (function() {
            // Monitor for page changes
            var observer = new MutationObserver(function(mutations) {
                try {
                    // Check for attack warnings
                    var attacks = document.querySelectorAll('.incoming_attack, [class*="attack"], .attack_warning');
                    if (attacks.length > 0) {
                        window.webkit.messageHandlers.gameObserver.postMessage({
                            type: 'attack_detected',
                            count: attacks.length
                        });
                    }
                    
                    // Check for resource full warnings
                    var fullWarnings = document.querySelectorAll('.warehouse_full, .granary_full, [class*="storage_full"]');
                    if (fullWarnings.length > 0) {
                        window.webkit.messageHandlers.gameObserver.postMessage({
                            type: 'storage_full'
                        });
                    }
                    
                    // Check for building complete
                    var buildComplete = document.querySelectorAll('.build_complete, [class*="complete"]');
                    if (buildComplete.length > 0) {
                        window.webkit.messageHandlers.gameObserver.postMessage({
                            type: 'build_complete'
                        });
                    }
                } catch(e) {}
            });
            
            observer.observe(document.body, {
                childList: true,
                subtree: true
            });
            
            // Monitor for new messages/alerts
            var originalAlert = window.alert;
            window.alert = function(msg) {
                window.webkit.messageHandlers.gameObserver.postMessage({
                    type: 'game_alert',
                    message: msg
                });
            };
        })();
        """
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var viewModel: WebViewModel
        
        init(viewModel: WebViewModel) {
            self.viewModel = viewModel
        }
        
        // MARK: - Navigation Delegate
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = true
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = false
                self.viewModel.currentURL = webView.url?.absoluteString ?? ""
            }
            
            // Inject automation scripts after page load
            if viewModel.isAutomationEnabled {
                viewModel.collectGameState()
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = false
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigation within the game
            decisionHandler(.allow)
        }
        
        // MARK: - UIDelegate
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Handle target="_blank" links by loading in same webview
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
        
        // MARK: - Script Message Handler
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            
            switch type {
            case "attack_detected":
                let count = body["count"] as? Int ?? 0
                viewModel.sendNotification(title: "⚠️ هجوم قادم!", body: "في \(count) هجوم جايين!")
                
            case "storage_full":
                viewModel.sendNotification(title: "📦 مخزن مليان!", body: "المخزن مليان - الموارد بتتوقف!")
                
            case "build_complete":
                viewModel.sendNotification(title: "🏗️ بناء خلص!", body: "مبنى جديد خلص بناؤه!")
                
            case "game_alert":
                let msg = body["message"] as? String ?? ""
                viewModel.sendNotification(title: "🎮 رسالة اللعبة", body: msg)
                
            default:
                break
            }
        }
    }
}
