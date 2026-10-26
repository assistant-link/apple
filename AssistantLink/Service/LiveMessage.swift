import Foundation

struct LinkStatusChange: Decodable, Equatable, Sendable {
  let linkID: String
  let status: Link.Status
  let lastActiveAt: Date?

  enum CodingKeys: String, CodingKey {
    case linkID = "link_id"
    case status
    case lastActiveAt = "last_active_at"
  }
}

/// A JSON-RPC 2.0 message from the app's live connection. Anything the app doesn't use
/// (responses, errors, unknown notifications, malformed frames) is `.ignored`.
enum LiveMessage: Equatable, Sendable {
  case linkStatus(LinkStatusChange)
  case eventCreated(Event)
  case eventUpdated(Event)
  case closing(reason: String)
  case ignored

  init(text: String) {
    let data = Data(text.utf8)
    let decoder = APIClient.decoder
    guard let header = try? decoder.decode(Header.self, from: data),
      header.jsonrpc == "2.0", !header.hasID
    else {
      self = .ignored
      return
    }
    switch header.method {
    case "link.status":
      self =
        (try? decoder.decode(Notification<LinkStatusChange>.self, from: data))
        .map { .linkStatus($0.params) } ?? .ignored
    case "event.created":
      self =
        (try? decoder.decode(Notification<EventParams>.self, from: data))
        .map { .eventCreated($0.params.event) } ?? .ignored
    case "event.updated":
      self =
        (try? decoder.decode(Notification<EventParams>.self, from: data))
        .map { .eventUpdated($0.params.event) } ?? .ignored
    case "connection.closing":
      self =
        (try? decoder.decode(Notification<Closing>.self, from: data))
        .map { .closing(reason: $0.params.reason) } ?? .ignored
    default:
      self = .ignored
    }
  }
}

private struct Header: Decodable {
  let jsonrpc: String
  let method: String
  /// Only requests and responses carry an `id`; the service's events are notifications.
  let hasID: Bool

  enum CodingKeys: String, CodingKey {
    case jsonrpc, method, id
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
    method = try container.decode(String.self, forKey: .method)
    hasID = container.contains(.id)
  }
}

private struct Notification<Params: Decodable>: Decodable {
  let params: Params
}

private struct EventParams: Decodable {
  let event: Event
}

private struct Closing: Decodable {
  let reason: String
}
