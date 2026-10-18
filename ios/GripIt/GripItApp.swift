import SwiftUI

@main
struct GripItApp: App {
  var body: some Scene {
    WindowGroup { StudioView() }
  }
}

@MainActor
final class StudioModel: ObservableObject {
  @Published var url: URL?
  @Published var error: String?
  @Published var export: ExportFile?
  private var server: LocalAssetServer?

  func start() {
    guard server == nil else { return }
    guard let root = Bundle.main.url(forResource: "Web", withExtension: nil),
      FileManager.default.fileExists(atPath: root.appendingPathComponent("index.html").path)
    else {
      error = "The studio assets are missing. Run npm run ios:prepare before building the app."
      return
    }
    let server = LocalAssetServer(root: root)
    self.server = server
    server.start { [weak self] result in
      Task { @MainActor in
        switch result {
        case .success(let url): self?.url = url
        case .failure(let error):
          self?.server?.stop()
          self?.server = nil
          self?.error = "Could not start the offline studio: \(error.localizedDescription)"
        }
      }
    }
  }
}

struct ExportFile: Identifiable {
  let id = UUID()
  let url: URL
}

struct StudioView: View {
  @StateObject private var model = StudioModel()
  @State private var reloadID = UUID()

  var body: some View {
    ZStack {
      Color(red: 0.92, green: 0.94, blue: 0.90).ignoresSafeArea()
      if let error = model.error {
        ContentUnavailableView {
          Label("Studio unavailable", systemImage: "baseball")
        } description: {
          Text(error)
        } actions: {
          Button("Retry") {
            model.error = nil
            reloadID = UUID()
            model.start()
          }
        }
      } else if let url = model.url {
        StudioWebView(url: url, model: model).id(reloadID)
      } else {
        ProgressView("Opening GripIt…")
      }
    }
    .preferredColorScheme(.light)
    .task { model.start() }
    .sheet(item: $model.export) { file in
      ShareSheet(url: file.url)
    }
  }
}

struct ShareSheet: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    controller.popoverPresentationController?.sourceView = controller.view
    controller.popoverPresentationController?.sourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    controller.popoverPresentationController?.permittedArrowDirections = []
    return controller
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
