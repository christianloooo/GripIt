import Foundation
import Network
import UniformTypeIdentifiers

/// Serves only bundled assets over loopback. An HTTP origin lets WebKit use
/// camera capture, WASM and classic workers without a remote hosting service.
final class LocalAssetServer {
  private let root: URL
  private let queue = DispatchQueue(label: "com.gripit.assets")
  private var listener: NWListener?
  private var connections: [UUID: NWConnection] = [:]
  private var didStart = false

  init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

  func start(port: NWEndpoint.Port = 49173, completion: @escaping (Result<URL, Error>) -> Void) {
    do {
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
      let listener = try NWListener(using: parameters)
      self.listener = listener
      listener.stateUpdateHandler = { [weak self, weak listener] state in
        guard let self else { return }
        switch state {
        case .ready:
          guard !self.didStart, let port = listener?.port else { return }
          self.didStart = true
          completion(.success(URL(string: "http://127.0.0.1:\(port.rawValue)/")!))
        case .failed(let error):
          if !self.didStart { completion(.failure(error)) }
        default: break
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        guard let self else {
          connection.cancel()
          return
        }
        let id = UUID()
        self.connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
          if case .cancelled = state { self?.connections.removeValue(forKey: id) }
        }
        connection.start(queue: self.queue)
        self.receive(connection, buffer: Data())
      }
      listener.start(queue: queue)
    } catch { completion(.failure(error)) }
  }

  func stop() {
    queue.async { [self] in
      listener?.cancel()
      listener = nil
      for connection in connections.values { connection.cancel() }
      connections.removeAll()
    }
  }

  private func receive(_ connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) {
      [weak self] data, _, complete, error in
      guard let self else {
        connection.cancel()
        return
      }
      var buffer = buffer
      if let data { buffer.append(data) }
      if buffer.count > 32768 {
        self.send(connection, status: "431 Request Header Fields Too Large")
        return
      }
      if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
        self.respond(connection, header: String(decoding: buffer[..<end.lowerBound], as: UTF8.self))
      } else if complete || error != nil {
        connection.cancel()
      } else {
        self.receive(connection, buffer: buffer)
      }
    }
  }

  private func respond(_ connection: NWConnection, header: String) {
    let request = header.components(separatedBy: "\r\n").first?.split(separator: " ") ?? []
    guard request.count == 3 else {
      send(connection, status: "400 Bad Request")
      return
    }
    let method = String(request[0])
    guard method == "GET" || method == "HEAD" else {
      send(connection, status: "405 Method Not Allowed")
      return
    }
    let rawPath = String(request[1]).components(separatedBy: "?")[0]
    guard let path = rawPath.removingPercentEncoding, path.hasPrefix("/"), !path.contains("\0"),
      !path.contains("\\")
    else {
      send(connection, status: "400 Bad Request")
      return
    }
    let relative = path == "/" ? "index.html" : String(path.dropFirst())
    let file = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
    guard file.path.hasPrefix(root.path + "/") else {
      send(connection, status: "403 Forbidden")
      return
    }
    guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else {
      send(connection, status: "404 Not Found")
      return
    }
    let types = [
      "wasm": "application/wasm", "js": "application/javascript", "mjs": "application/javascript",
      "css": "text/css", "html": "text/html; charset=utf-8", "json": "application/json",
      "glb": "model/gltf-binary", "task": "application/octet-stream",
    ]
    let type =
      types[file.pathExtension] ?? UTType(filenameExtension: file.pathExtension)?.preferredMIMEType
      ?? "application/octet-stream"
    send(connection, status: "200 OK", body: data, type: type, head: method == "HEAD")
  }

  private func send(
    _ connection: NWConnection, status: String, body: Data = Data(), type: String = "text/plain",
    head: Bool = false
  ) {
    var response = Data(
      "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache\r\n\r\n"
        .utf8)
    if !head { response.append(body) }
    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
  }
}
