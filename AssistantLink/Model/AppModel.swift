import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class AppModel {
  enum Phase: Equatable {
    case loading
    case ready
    case failed(String)
  }

  private(set) var phase = Phase.loading
  private(set) var assistants: [Assistant] = []
  /// Changes whenever the app starts using an account, so live updates restart with it.
  private(set) var session = 0

  private static let logger = Logger(subsystem: "ai.assistantlink.app", category: "live")

  private let connect: @Sendable () async throws -> APIClient
  private let forget: @Sendable () throws -> Void
  private let makeLiveUpdates: @MainActor (APIClient) -> LiveUpdates?
  private var api: APIClient?
  private var pairingCodes: [Link.ID: PairingCode] = [:]

  init(
    connect: @escaping @Sendable () async throws -> APIClient,
    forget: @escaping @Sendable () throws -> Void = {},
    liveUpdates: @escaping @MainActor (APIClient) -> LiveUpdates? = LiveUpdates.live
  ) {
    self.connect = connect
    self.forget = forget
    self.makeLiveUpdates = liveUpdates
  }

  static func live() -> AppModel {
    let baseURL = ServiceConfiguration.baseURL()
    let store = KeychainCredentialStore(account: baseURL.absoluteString)
    return AppModel(
      connect: { try await AccountSession.connect(baseURL: baseURL, store: store) },
      forget: { try store.delete() })
  }

  static func preview(_ assistants: [Assistant]) -> AppModel {
    let model = AppModel(connect: { throw APIError.unreachable })
    model.assistants = assistants
    model.phase = .ready
    return model
  }

  func start() async {
    phase = .loading
    do {
      let api = try await connect()
      self.api = api
      session += 1
      assistants = try await api.listAssistants()
      phase = .ready
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  func refresh() async throws {
    assistants = try await client().listAssistants()
  }

  /// Keeps statuses current until cancelled. Each time the live connection opens, the
  /// Assistants are fetched again, because changes made while it was closed were never sent.
  func runLiveUpdates() async {
    guard let api, let updates = makeLiveUpdates(api) else { return }
    let session = session
    let stop = await updates.run(
      onOpen: {
        guard let assistants = try? await api.listAssistants(), self.session == session else {
          return
        }
        self.assistants = assistants
        phase = .ready
      },
      onLinkStatus: { apply($0) })
    if let stop {
      Self.logger.notice("Live updates stopped: \(String(describing: stop), privacy: .public)")
    }
  }

  func apply(_ change: LinkStatusChange) {
    for index in assistants.indices {
      guard let linkIndex = assistants[index].links.firstIndex(where: { $0.id == change.linkID })
      else { continue }
      assistants[index].links[linkIndex].status = change.status
      assistants[index].links[linkIndex].lastActiveAt =
        change.lastActiveAt ?? assistants[index].links[linkIndex].lastActiveAt
      assistants[index].status =
        assistants[index].links.contains { $0.status == .online } ? .online : .offline
      return
    }
  }

  /// Deletes the account and everything it owns, then registers a new one as on first launch.
  func logOut() async throws {
    do {
      try await client().deleteAccount()
    } catch APIError.service(status: 401, code: _, message: _) {
      // The service no longer accepts this credential, so its account is already gone.
    }
    try forget()
    api = nil
    assistants = []
    pairingCodes = [:]
    await start()
  }

  func assistant(id: Assistant.ID) -> Assistant? {
    assistants.first { $0.id == id }
  }

  func createAssistant(name: String, avatar: String) async throws -> Assistant {
    let assistant = try await client().createAssistant(name: name, avatar: avatar)
    assistants.append(assistant)
    return assistant
  }

  func createLink(assistantID: Assistant.ID) async throws -> Link {
    let link = try await client().createLink(assistantID: assistantID)
    if let index = assistants.firstIndex(where: { $0.id == assistantID }) {
      assistants[index].links.append(link)
    }
    return link
  }

  /// Reuses the Link's unexpired code, because issuing a new one invalidates the code the
  /// user may already have pasted to their agent.
  func pairingCode(linkID: Link.ID, renew: Bool = false) async throws -> PairingCode {
    if !renew, let code = pairingCodes[linkID], code.expiresAt > .now {
      return code
    }
    let code = try await client().issuePairingCode(linkID: linkID)
    pairingCodes[linkID] = code
    return code
  }

  private func client() async throws -> APIClient {
    if let api { return api }
    let api = try await connect()
    self.api = api
    return api
  }
}
