import Foundation
import Security

protocol CredentialStore: Sendable {
  func load() throws -> String?
  func save(_ credential: String) throws
  func delete() throws
}

struct KeychainError: Error, Equatable {
  let status: OSStatus
}

/// Stores the account credential as a generic password, one per service URL (`account`),
/// so pointing a debug build at another service never sends it this credential.
struct KeychainCredentialStore: CredentialStore {
  let service: String
  let account: String

  init(service: String = "ai.assistantlink.app.account-credential", account: String) {
    self.service = service
    self.account = account
  }

  func load() throws -> String? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else { return nil }
      return String(decoding: data, as: UTF8.self)
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainError(status: status)
    }
  }

  func save(_ credential: String) throws {
    let data = Data(credential.utf8)
    let status = SecItemUpdate(
      baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = baseQuery
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let addStatus = SecItemAdd(item as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    } else if status != errSecSuccess {
      throw KeychainError(status: status)
    }
  }

  func delete() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError(status: status)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
