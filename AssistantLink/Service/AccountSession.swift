import Foundation
import OSLog

enum AccountSession {
  private static let logger = Logger(subsystem: "ai.assistantlink.app", category: "account")

  /// Returns a client for the stored account, registering a new account on first launch.
  static func connect(
    baseURL: URL, store: some CredentialStore, session: URLSession = .shared
  ) async throws -> APIClient {
    if let credential = try store.load() {
      return APIClient(baseURL: baseURL, credential: credential, session: session)
    }
    let registration = try await APIClient(baseURL: baseURL, credential: nil, session: session)
      .register()
    try store.save(registration.credential)
    logger.notice(
      "Registered account \(registration.accountID, privacy: .public) with \(baseURL, privacy: .public)"
    )
    return APIClient(baseURL: baseURL, credential: registration.credential, session: session)
  }
}
