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
  enum Status: String, ForwardCompatibleEnum, Sendable {
    case online
    /// No agent is connected, but writing wakes one through the Link's webhook.
    case idle
    case offline

    static let fallback = offline

    init(links: [Link.Status]) {
      if links.contains(.online) {
        self = .online
      } else if links.contains(.idle) {
        self = .idle
      } else {
        self = .offline
      }
    }
  }

  let id: String
  var name: String
  var avatar: String
  var status: Status
  @LossyArray var links: [Link]
  @LossyOptional var latestEvent: Event? = nil
  /// What the agent says it runs on, free-form. Not shown yet.
  @LossyOptional var platform: String? = nil

  enum CodingKeys: String, CodingKey {
    case id, name, avatar, status, links, platform
    case latestEvent = "latest_event"
  }
}

struct Link: Decodable, Equatable, Identifiable, Sendable {
  enum Status: String, ForwardCompatibleEnum, Sendable {
    case notPaired = "not_paired"
    case online
    /// No agent is connected, but writing wakes one through the Link's webhook.
    case idle
    case offline

    static let fallback = offline
  }

  let id: String
  var label: String?
  var status: Status
  var lastActiveAt: Date?
  /// What the agent says it is doing. Only live, never stored.
  @ActivityText var activity: String? = nil
  /// `nil` when the service doesn't say how its Links are woken, as before it could.
  var wake: Wake? = nil
}

extension Link {
  private enum CodingKeys: String, CodingKey {
    case id
    case label
    case status
    case lastActiveAt = "last_active_at"
    case activity
    case webhookInstalled = "webhook_installed"
    case wakeEmail = "wake_email"
    case wakeRoute = "wake_route"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    label = try container.decodeIfPresent(String.self, forKey: .label)
    status = try container.decode(Status.self, forKey: .status)
    lastActiveAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveAt)
    _activity = container.decode(ActivityText.self, forKey: .activity)
    // A service that knows wake routes sends all three keys, even when they are null.
    let wakeKeys: [CodingKeys] = [.webhookInstalled, .wakeEmail, .wakeRoute]
    guard wakeKeys.contains(where: container.contains) else { return }
    let installed = try? container.decodeIfPresent(Bool.self, forKey: .webhookInstalled)
    let email = container.decode(LossyOptional<Wake.Email>.self, forKey: .wakeEmail).wrappedValue
    let route: Wake.Route? =
      if container.contains(.wakeRoute) {
        Wake.Route(container.decode(LossyOptional<String>.self, forKey: .wakeRoute).wrappedValue)
      } else {
        nil
      }
    wake = Wake(
      webhookInstalled: installed ?? false,
      email: email?.address.isEmpty == false ? email : nil,
      route: route)
  }
}

/// How the service wakes a Link's agent when none is connected. A webhook's URL and secret never
/// reach the app.
struct Wake: Equatable, Sendable {
  enum Route: Sendable {
    case webhook
    case email
    /// Also a route this app doesn't know.
    case noRoute

    init(_ value: String?) {
      self =
        switch value {
        case "webhook": .webhook
        case "email": .email
        default: .noRoute
        }
    }
  }

  struct Email: Decodable, Equatable, Sendable {
    let address: String
    /// An email wakes the agent only once its address is confirmed.
    let confirmed: Bool
  }

  var webhookInstalled = false
  var email: Email?
  /// The active route, or `nil` when the service doesn't say which one it is.
  var route: Route?
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
  enum Kind: String, ForwardCompatibleEnum, Sendable {
    case textMessage = "text_message"
    case linkCreated = "link_created"
    case callStarted = "call_started"
    case callEnded = "call_ended"
    case unknown

    static let fallback = unknown
  }

  enum Sender: String, ForwardCompatibleEnum, Sendable {
    case user
    case assistant
    case system
    case unknown

    static let fallback = unknown
  }

  enum DeliveryStatus: String, ForwardCompatibleEnum, Sendable {
    case sent
    case delivered
    case unknown

    static let fallback = unknown
  }

  /// How the user made a text message, when not by typing it. Unlike the other enums, it has no
  /// fallback: the app sends it, and a value it doesn't know decodes as `nil`.
  enum Via: String, Codable, Sendable {
    case voice
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
  var via: Via?
  /// The id of the message this one answers, which may no longer exist.
  var replyTo: String?
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
    case replyTo = "reply_to"
  }

  private struct TextContent: Decodable {
    let text: String
    @LossyOptional var via: Via?
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    assistantID = try container.decode(String.self, forKey: .assistantID)
    type = try container.decode(Kind.self, forKey: .type)
    sender = try container.decode(Sender.self, forKey: .sender)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    linkID = try container.decodeIfPresent(String.self, forKey: .linkID)
    deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    deliveryStatus = try container.decodeIfPresent(DeliveryStatus.self, forKey: .deliveryStatus)
    idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey)
    let content = try container.decodeIfPresent(TextContent.self, forKey: .textMessage)
    text = content?.text
    via = content?.via
    replyTo = container.decode(LossyOptional<String>.self, forKey: .replyTo).wrappedValue
  }
}

/// One page of an Assistant's events, oldest first.
struct EventPage: Equatable, Sendable {
  var events: [Event]
  /// Whether events older than the first one exist.
  var hasMore: Bool
}
