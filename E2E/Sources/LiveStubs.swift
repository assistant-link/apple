import Foundation

// What `AppModel.live()` names. The E2E builds its own AppModel, so these are never called.
struct KeychainCredentialStore {
  init(account: String) {}
  func delete() throws {}
}

enum AccountSession {
  static func connect(baseURL: URL, store: KeychainCredentialStore) async throws -> APIClient {
    fatalError()
  }
}

extension VoiceCall {
  static func live() -> VoiceCall { fatalError() }
}
