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
