import Foundation

enum APIError: Error, Equatable, LocalizedError {
  /// The service answered with its `{"error": {"code", "message"}}` body.
  case service(status: Int, code: String, message: String)
  case unexpectedResponse(status: Int)
  case unreachable

  var errorDescription: String? {
    switch self {
    case .service(_, _, let message):
      message
    case .unexpectedResponse(let status):
      "Assistant Link answered with an unexpected response (HTTP \(status)). Try again."
    case .unreachable:
      "Can't reach Assistant Link. Check your connection and try again."
    }
  }
}

/// The client API under `/api/v1`, authenticated with the account credential.
struct APIClient: Sendable {
  let baseURL: URL
  let credential: String?
  let session: URLSession

  init(baseURL: URL, credential: String?, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.credential = credential
    self.session = session
  }

  func register() async throws -> Registration {
    try await send("POST", "accounts", body: [String: String]())
  }

  func listAssistants() async throws -> [Assistant] {
    let response: AssistantsResponse = try await send("GET", "assistants")
    return response.assistants
  }

  func createAssistant(name: String, avatar: String) async throws -> Assistant {
    let response: AssistantResponse = try await send(
      "POST", "assistants", body: ["name": name, "avatar": avatar])
    return response.assistant
  }

  func createLink(assistantID: String) async throws -> Link {
    let response: LinkResponse = try await send(
      "POST", "assistants/\(assistantID)/links", body: [String: String]())
    return response.link
  }

  func issuePairingCode(linkID: String) async throws -> PairingCode {
    try await send("POST", "links/\(linkID)/pairing_code", body: [String: String]())
  }

  func deleteAccount() async throws {
    _ = try await perform("DELETE", "account")
  }

  /// The WebSocket request for `/api/v1/connect`, or `nil` without a credential.
  func liveConnectionRequest() -> URLRequest? {
    guard let credential,
      var components = URLComponents(
        url: baseURL.appending(path: "api/v1/connect"), resolvingAgainstBaseURL: false)
    else { return nil }
    components.scheme = components.scheme == "http" ? "ws" : "wss"
    guard let url = components.url else { return nil }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    return request
  }

  private func send<Response: Decodable>(
    _ method: String, _ path: String, body: (some Encodable)? = String?.none
  ) async throws -> Response {
    let (data, status) = try await perform(method, path, body: body)
    do {
      return try Self.decoder.decode(Response.self, from: data)
    } catch {
      throw APIError.unexpectedResponse(status: status)
    }
  }

  private func perform(
    _ method: String, _ path: String, body: (some Encodable)? = String?.none
  ) async throws -> (Data, Int) {
    var request = URLRequest(url: baseURL.appending(path: "api/v1/\(path)"))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let credential {
      request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw APIError.unreachable
    }

    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      if let body = try? Self.decoder.decode(ErrorResponse.self, from: data) {
        throw APIError.service(status: status, code: body.error.code, message: body.error.message)
      }
      throw APIError.unexpectedResponse(status: status)
    }
    return (data, status)
  }

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      if let date = try? Date(
        value, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))
      {
        return date
      }
      if let date = try? Date(value, strategy: .iso8601) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Not an ISO 8601 date: \(value)")
    }
    return decoder
  }()
}

private struct AssistantsResponse: Decodable {
  let assistants: [Assistant]
}

private struct AssistantResponse: Decodable {
  let assistant: Assistant
}

private struct LinkResponse: Decodable {
  let link: Link
}

private struct ErrorResponse: Decodable {
  struct Body: Decodable {
    let code: String
    let message: String
  }

  let error: Body
}
