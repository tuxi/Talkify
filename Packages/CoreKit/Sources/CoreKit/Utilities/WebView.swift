import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

#if canImport(WebKit)

public func openExternalURL(_ urlStr: String) {
    guard let url = URL(string: urlStr) else { return }
    openExternalURL(url)
}

public func openExternalURL(_ url: URL) {
#if os(iOS)
    UIApplication.shared.open(url)
#elseif os(macOS)
    NSWorkspace.shared.open(url)
#endif
}


// MARK: - BrowserView

@MainActor @Observable
public final class BrowserViewModel {
    public var canGoBack = false
    public var canGoForward = false
    public var isLoading = false
    public var pageTitle = ""
    /// 当前实际浏览到的页面 URL（随站内跳转更新）。
    public var currentURL: URL?

    @ObservationIgnored
    var webView: WKWebView?

    public func goBack() { webView?.goBack() }
    public func goForward() { webView?.goForward() }
    public func reload() { webView?.reload() }
}

public struct BrowserView: View {
    let url: URL
    let importActionTitle: String?
    let onImport: ((URL) -> Void)?
    @State private var viewModel = BrowserViewModel()
    @Environment(\.dismiss) private var dismiss

    public init(
        url: URL,
        importActionTitle: String? = nil,
        onImport: ((URL) -> Void)? = nil
    ) {
        self.url = url
        self.importActionTitle = importActionTitle
        self.onImport = onImport
    }

    public var body: some View {
        content
    }

    /// 当前页面 URL，未取到时回退到初始 URL。
    private var resolvedCurrentURL: URL {
        viewModel.currentURL ?? url
    }

    private var content: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
            WebView(url: url, viewModel: viewModel)
        }
        #if os(iOS)
        .navigationTitle(viewModel.pageTitle.isEmpty ? "浏览" : viewModel.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { viewModel.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!viewModel.canGoBack)

                Button { viewModel.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!viewModel.canGoForward)

                Spacer()

                Button { viewModel.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            if let onImport {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onImport(resolvedCurrentURL)
                    } label: {
                        Text(importActionTitle ?? "导入")
                            .fontWeight(.semibold)
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        #else
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            if let onImport {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onImport(resolvedCurrentURL)
                    } label: {
                        Text(importActionTitle ?? "导入")
                            .fontWeight(.semibold)
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        #endif
    }
}

// MARK: - WebView platform wrapper

#if os(iOS)
public struct WebView: UIViewRepresentable {
    let url: URL
    let viewModel: BrowserViewModel

    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        viewModel.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url == nil || webView.url?.absoluteString != url.absoluteString {
            webView.load(URLRequest(url: url))
        }
    }

    public class Coordinator: NSObject, WKNavigationDelegate {
        let viewModel: BrowserViewModel

        init(_ viewModel: BrowserViewModel) { self.viewModel = viewModel }

        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.isLoading = true
                viewModel.canGoBack = webView.canGoBack
                viewModel.canGoForward = webView.canGoForward
            }
        }

        public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.currentURL = webView.url
            }
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.isLoading = false
                viewModel.pageTitle = webView.title ?? ""
                viewModel.currentURL = webView.url
                viewModel.canGoBack = webView.canGoBack
                viewModel.canGoForward = webView.canGoForward
            }
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in viewModel.isLoading = false }
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            Task { @MainActor in viewModel.isLoading = false }
        }
    }
}

#elseif os(macOS)
public struct WebView: NSViewRepresentable {
    let url: URL
    let viewModel: BrowserViewModel

    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        viewModel.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url == nil || webView.url?.absoluteString != url.absoluteString {
            webView.load(URLRequest(url: url))
        }
    }

    public class Coordinator: NSObject, WKNavigationDelegate {
        let viewModel: BrowserViewModel

        init(_ viewModel: BrowserViewModel) { self.viewModel = viewModel }

        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.isLoading = true
                viewModel.canGoBack = webView.canGoBack
                viewModel.canGoForward = webView.canGoForward
            }
        }

        public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.currentURL = webView.url
            }
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.isLoading = false
                viewModel.pageTitle = webView.title ?? ""
                viewModel.currentURL = webView.url
                viewModel.canGoBack = webView.canGoBack
                viewModel.canGoForward = webView.canGoForward
            }
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in viewModel.isLoading = false }
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            Task { @MainActor in viewModel.isLoading = false }
        }
    }
}
#endif

#endif // canImport(WebKit)
