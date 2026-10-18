import AVFoundation
import SwiftUI
import WebKit

struct StudioWebView: UIViewRepresentable {
  let url: URL
  let model: StudioModel

  func makeCoordinator() -> Coordinator { Coordinator(model: model, origin: url) }
  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.allowsInlineMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.websiteDataStore = .default()
    configuration.userContentController.add(context.coordinator, name: "gripit")
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.uiDelegate = context.coordinator
    view.navigationDelegate = context.coordinator
    view.isOpaque = false
    view.backgroundColor = .clear
    view.scrollView.contentInsetAdjustmentBehavior = .never
    view.allowsBackForwardNavigationGestures = false
    view.load(URLRequest(url: url))
    return view
  }
  func updateUIView(_ view: WKWebView, context: Context) {}
  static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
    view.stopLoading()
    view.configuration.userContentController.removeScriptMessageHandler(forName: "gripit")
    view.setAllMediaPlaybackSuspended(true)
  }

  @MainActor
  final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private let model: StudioModel
    private let origin: URL
    init(model: StudioModel, origin: URL) {
      self.model = model
      self.origin = origin
    }

    private func isStudio(_ url: URL?) -> Bool {
      url?.scheme == origin.scheme && url?.host == origin.host && url?.port == origin.port
    }

    func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard let url = navigationAction.request.url else {
        decisionHandler(.cancel)
        return
      }
      if isStudio(url) || url.absoluteString == "about:blank" {
        decisionHandler(.allow)
        return
      }
      decisionHandler(.cancel)
      if navigationAction.navigationType == .linkActivated
        && ["https", "http"].contains(url.scheme ?? "")
      {
        UIApplication.shared.open(url)
      }
    }

    func webView(
      _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
      initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
      decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
      guard origin.protocol == "http", origin.host == self.origin.host,
        origin.port == self.origin.port, frame.isMainFrame, type == .camera
      else {
        decisionHandler(.deny)
        return
      }
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: decisionHandler(.grant)
      case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { allowed in
          Task { @MainActor in decisionHandler(allowed ? .grant : .deny) }
        }
      default: decisionHandler(.deny)
      }
    }

    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      guard message.frameInfo.isMainFrame, isStudio(message.frameInfo.request.url),
        let payload = message.body as? [String: String], payload["action"] == "export",
        let filename = payload["filename"], filename.hasSuffix(".json"),
        filename == (filename as NSString).lastPathComponent,
        let content = payload["content"], let data = content.data(using: .utf8),
        data.count <= 2_000_000
      else { return }
      do {
        // Stable filename, app-private Documents directory; old exports are overwritten.
        let directory = try FileManager.default.url(
          for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let file = directory.appendingPathComponent(filename)
        try data.write(to: file, options: .atomic)
        model.export = ExportFile(url: file)
      } catch { model.error = "Could not share the export: \(error.localizedDescription)" }
    }

    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      if (error as NSError).code != NSURLErrorCancelled { model.error = error.localizedDescription }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      model.error = "The 3D studio stopped. Tap Retry to reload it."
    }
  }
}
