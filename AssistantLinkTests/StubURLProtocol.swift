import Foundation
import Synchronization

/// Answers requests from a per-session handler, so tests running in parallel each get their own.
final class StubURLProtocol: URLProtocol {
  typealias Handler = @Sendable (URLRequest, Data?) throws -> (Int, Data)

  private static let handlers = Mutex<[String: Handler]>([:])
  private static let stubHeader = "X-Stub-ID"

  static func session(_ handler: @escaping Handler) -> URLSession {
    let id = UUID().uuidString
    handlers.withLock { $0[id] = handler }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    configuration.httpAdditionalHeaders = [stubHeader: id]
    return URLSession(configuration: configuration)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let id = request.value(forHTTPHeaderField: Self.stubHeader) ?? ""
    guard let handler = Self.handlers.withLock({ $0[id] }) else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    do {
      let (status, data) = try handler(request, Self.body(of: request))
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}

  /// URLSession hands protocols the body as a stream, never as `httpBody`.
  private static func body(of request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

extension Data {
  init(json: String) { self = Data(json.utf8) }

  func jsonObject() throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: self) as? [String: Any] ?? [:]
  }
}
