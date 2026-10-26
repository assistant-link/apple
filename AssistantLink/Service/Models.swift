import Foundation

struct Registration: Decodable, Equatable, Sendable {
  let accountID: String
  let credential: String

  enum CodingKeys: String, CodingKey {
    case accountID = "account_id"
    case credential
  }
}

struct Assistant: Decodable, Equatable, Identifiable, Sendable {
  enum Status: String, Decodable, Sendable {
    case online
    case offline
  }

  let id: String
  var name: String
  var avatar: String
  var status: Status
  var links: [Link]
  var latestEvent: Event?

  enum CodingKeys: String, CodingKey {
    case id, name, avatar, status, links
    case latestEvent = "latest_event"
  }
}

struct Link: Decodable, Equatable, Identifiable, Sendable {
  enum Status: String, Decodable, Sendable {
    case notPaired = "not_paired"
    case online
    case offline
  }

  let id: String
  var label: String?
  var status: Status
  var lastActiveAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case label
    case status
    case lastActiveAt = "last_active_at"
  }
}

struct PairingCode: Decodable, Equatable, Sendable {
  let code: String
  let expiresAt: Date
  let pairingText: String

  enum CodingKeys: String, CodingKey {
    case code
    case expiresAt = "expires_at"
    case pairingText = "pairing_text"
  }
}

/// A stored item of an Assistant's conversation, as the app API returns it.
struct Event: Decodable, Equatable, Identifiable, Sendable {
  enum Kind: String, Decodable, Sendable {
    case textMessage = "text_message"
    case linkCreated = "link_created"
  }

  enum Sender: String, Decodable, Sendable {
    case user
    case assistant
    case system
  }

  enum DeliveryStatus: String, Decodable, Sendable {
    case sent
    case delivered
  }

  let id: String
  let assistantID: String
  let type: Kind
  let sender: Sender
  let createdAt: Date
  var linkID: String?
  /// A `text_message` whose text was deleted keeps its place, with no `text`.
  var deleted = false
  var deliveryStatus: DeliveryStatus?
  var idempotencyKey: String?
  var text: String?
}

extension Event {
  private enum CodingKeys: String, CodingKey {
    case id, type, sender, deleted
    case assistantID = "assistant_id"
    case linkID = "link_id"
    case createdAt = "created_at"
    case deliveryStatus = "delivery_status"
    case idempotencyKey = "idempotency_key"
    case textMessage = "text_message"
  }

  private struct TextContent: Decodable {
    let text: String
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    assistantID = try container.decode(String.self, forKey: .assistantID)
    type = try container.decode(Kind.self, forKey: .type)
    sender = try container.decode(Sender.self, forKey: .sender)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    linkID = try container.decodeIfPresent(String.self, forKey: .linkID)
    deleted = try container.decode(Bool.self, forKey: .deleted)
    deliveryStatus = try container.decodeIfPresent(DeliveryStatus.self, forKey: .deliveryStatus)
    idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey)
    text = try container.decodeIfPresent(TextContent.self, forKey: .textMessage)?.text
  }
}

/// One page of an Assistant's events, oldest first.
struct EventPage: Equatable, Sendable {
  var events: [Event]
  /// Whether events older than the first one exist.
  var hasMore: Bool
}
