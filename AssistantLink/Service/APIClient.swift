import Foundation

enum APIError: Error, Equatable, LocalizedError {
  /// The service answered with its `{"error": {"code", "message"}}` body.
  case service(status: Int, code: String, message: String)
  case unexpectedResponse(status: Int)
  case unreachable

  /// Whether sending the same request again later may succeed.
  var isTransient: Bool {
    switch self {
    case .unreachable: true
    case .unexpectedResponse(let status), .service(let status, _, _):
      status >= 500 || status == 408 || status == 429
    }
  }

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

  /// The newest `limit` events, or the `limit` events before the event `before`.
  func events(assistantID: String, limit: Int, before: String? = nil) async throws -> EventPage {
    var query = [URLQueryItem(name: "limit", value: String(limit))]
    if let before {
      query.append(URLQueryItem(name: "before", value: before))
    }
    let response: EventsResponse = try await send(
      "GET", "assistants/\(assistantID)/events", query: query)
    return EventPage(events: response.events, hasMore: response.hasMore)
  }

  /// Posting the same `idempotencyKey` again returns the stored event instead of a new one.
  func sendMessage(
    assistantID: String, text: String, idempotencyKey: String, via: Event.Via? = nil,
    replyTo: String? = nil
  ) async throws -> Event {
    let response: MessageResponse = try await send(
      "POST", "assistants/\(assistantID)/messages",
      body: MessageRequest(text: text, idempotencyKey: idempotencyKey, via: via, replyTo: replyTo))
    return response.message
  }

  /// Posting the same `idempotencyKey` again returns the stored event instead of a new one.
  func sendCallEvent(
    assistantID: String, type: Event.Kind, idempotencyKey: String
  ) async throws -> Event {
    let response: CallEventResponse = try await send(
      "POST", "assistants/\(assistantID)/call_events",
      body: ["type": type.rawValue, "idempotency_key": idempotencyKey])
    return response.event
  }

  /// Starts a voice chat, which the service also writes as a `call_started` and a `voice_call`.
  /// A service from before calls were sessions answers 404.
  func startCall(assistantID: String) async throws -> CallSession {
    let response: Envelope<CallSession> = try await send(
      "POST", "assistants/\(assistantID)/calls", body: [String: String]())
    return response.value
  }

  /// The user hung up; the service writes the `call_ended` and updates the `voice_call`.
  func endCall(assistantID: String, callID: String) async throws {
    _ = try await perform(
      "POST", "assistants/\(assistantID)/calls/\(callID)/end", body: [String: String]())
  }

  /// The call's spoken turns, in the order they were saved.
  func transcript(assistantID: String, callID: String) async throws -> [CallTranscriptEntry] {
    let response: TranscriptResponse = try await send(
      "GET", "assistants/\(assistantID)/calls/\(callID)/transcript")
    return response.entries.sorted { $0.seq < $1.seq }
  }

  /// `endedAt` is `nil` while the turn is still being said.
  func saveTranscriptEntry(
    assistantID: String, callID: String, speaker: CallTranscriptEntry.Speaker, text: String,
    startedAt: Date, endedAt: Date?
  ) async throws -> CallTranscriptEntry {
    let response: Envelope<CallTranscriptEntry> = try await send(
      "POST", "assistants/\(assistantID)/calls/\(callID)/transcript_entries",
      body: TranscriptEntryRequest(
        speaker: speaker, text: text, startedAt: startedAt, endedAt: endedAt))
    return response.value
  }

  func updateTranscriptEntry(
    assistantID: String, callID: String, entryID: String, endedAt: Date
  ) async throws {
    _ = try await perform(
      "PATCH", "assistants/\(assistantID)/calls/\(callID)/transcript_entries/\(entryID)",
      body: TranscriptEntryRequest(endedAt: endedAt))
  }

  /// Asks the service to wake the Assistants that have a webhook, so they show as online.
  func wake() async throws {
    _ = try await perform("POST", "wake")
  }

  /// Pushes for the account reach this device through its APNs token, which replaces any
  /// earlier one.
  func setPushToken(_ token: String) async throws {
    _ = try await perform("PUT", "device/push_token", body: ["token": token])
  }

  func deletePushToken() async throws {
    _ = try await perform("DELETE", "device/push_token")
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
    _ method: String, _ path: String, query: [URLQueryItem] = [],
    body: (some Encodable)? = String?.none
  ) async throws -> Response {
    let (data, status) = try await perform(method, path, query: query, body: body)
    do {
      return try Self.decoder.decode(Response.self, from: data)
    } catch {
      throw APIError.unexpectedResponse(status: status)
    }
  }

  private func perform(
    _ method: String, _ path: String, query: [URLQueryItem] = [],
    body: (some Encodable)? = String?.none
  ) async throws -> (Data, Int) {
    var url = baseURL.appending(path: "api/v1/\(path)")
    if !query.isEmpty {
      url.append(queryItems: query)
    }
    var request = URLRequest(url: url)
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
  @LossyArray var assistants: [Assistant]
}

private struct AssistantResponse: Decodable {
  let assistant: Assistant
}

private struct LinkResponse: Decodable {
  let link: Link
}

private struct EventsResponse: Decodable {
  @LossyArray var events: [Event]
  let hasMore: Bool

  enum CodingKeys: String, CodingKey {
    case events
    case hasMore = "has_more"
  }
}

private struct MessageRequest: Encodable {
  let text: String
  let idempotencyKey: String
  let via: Event.Via?
  /// Left out, not `null`, when the message answers nothing.
  let replyTo: String?

  enum CodingKeys: String, CodingKey {
    case text, via
    case idempotencyKey = "idempotency_key"
    case replyTo = "reply_to"
  }
}

/// A resource the service answers with under its own name, as for the other resources.
private protocol NamedResource: Decodable {
  static var name: String { get }
}

extension CallSession: NamedResource {
  static let name = "call"
}

extension CallTranscriptEntry: NamedResource {
  static let name = "transcript_entry"
}

/// The resource under its name, or on its own.
private struct Envelope<Value: NamedResource>: Decodable {
  let value: Value

  private struct Key: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }

  init(from decoder: any Decoder) throws {
    if let container = try? decoder.container(keyedBy: Key.self),
      let value = try? container.decode(Value.self, forKey: Key(stringValue: Value.name))
    {
      self.value = value
    } else {
      value = try Value(from: decoder)
    }
  }
}

private struct TranscriptResponse: Decodable {
  let entries: [CallTranscriptEntry]

  enum CodingKeys: String, CodingKey {
    case transcriptEntries = "transcript_entries"
    case entries
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let key: CodingKeys = container.contains(.transcriptEntries) ? .transcriptEntries : .entries
    entries = try container.decode(LossyArray<CallTranscriptEntry>.self, forKey: key).wrappedValue
  }
}

/// Leaves out what it doesn't set, so an update changes only `ended_at`.
private struct TranscriptEntryRequest: Encodable {
  var speaker: CallTranscriptEntry.Speaker?
  var text: String?
  var startedAt: Date?
  var endedAt: Date?

  enum CodingKeys: String, CodingKey {
    case speaker, text
    case startedAt = "started_at"
    case endedAt = "ended_at"
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(speaker, forKey: .speaker)
    try container.encodeIfPresent(text, forKey: .text)
    try container.encodeIfPresent(startedAt.map(Self.timestamp), forKey: .startedAt)
    try container.encodeIfPresent(endedAt.map(Self.timestamp), forKey: .endedAt)
  }

  private static func timestamp(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
  }
}

private struct CallEventResponse: Decodable {
  let event: Event
}

private struct MessageResponse: Decodable {
  let message: Event
}

private struct ErrorResponse: Decodable {
  struct Body: Decodable {
    let code: String
    let message: String
  }

  let error: Body
}
