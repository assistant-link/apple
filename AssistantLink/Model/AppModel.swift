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
  /// The conversations opened so far, by Assistant.
  private(set) var timelines: [Assistant.ID: Timeline] = [:]
  /// Changes whenever the app starts using an account, so live updates restart with it.
  private(set) var session = 0

  private static let pageSize = 50
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

  static func preview(
    _ assistants: [Assistant], timelines: [Assistant.ID: Timeline] = [:]
  ) -> AppModel {
    let model = AppModel(connect: { throw APIError.unreachable })
    model.assistants = assistants
    model.timelines = timelines
    model.phase = .ready
    return model
  }

  func start() async {
    phase = .loading
    do {
      let api = try await connect()
      self.api = api
      session += 1
      timelines = [:]
      assistants = try await api.listAssistants()
      phase = .ready
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  func refresh() async throws {
    assistants = try await client().listAssistants()
  }

  /// Keeps statuses and conversations current until cancelled. Each time the live connection
  /// opens, the Assistants and the opened conversations' latest events are fetched again,
  /// because changes made while it was closed were never sent. The connection opens again
  /// whenever the app returns to the foreground.
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
        for id in timelines.keys {
          try? await loadLatest(assistantID: id, using: api)
        }
      },
      onLinkStatus: { apply($0) },
      onEventCreated: { apply(created: $0) },
      onEventUpdated: { apply(updated: $0) })
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

  func apply(created event: Event) {
    timelines[event.assistantID]?.receive(event)
    setLatestEvent(event, onlyIfLatest: false)
  }

  func apply(updated event: Event) {
    timelines[event.assistantID]?.update(event)
    setLatestEvent(event, onlyIfLatest: true)
  }

  /// Loads the conversation's latest events when it opens. The timeline exists before the
  /// fetch so live events arriving meanwhile are kept, and so a failed fetch is retried when
  /// the live connection opens again.
  func openConversation(assistantID: Assistant.ID) async throws {
    let api = try await client()
    if timelines[assistantID] == nil {
      timelines[assistantID] = Timeline()
    }
    try await loadLatest(assistantID: assistantID, using: api)
  }

  func loadEarlier(assistantID: Assistant.ID) async throws {
    guard let oldest = timelines[assistantID]?.events.first else { return }
    let session = session
    let page = try await client().events(
      assistantID: assistantID, limit: Self.pageSize, before: oldest.id)
    guard self.session == session, timelines[assistantID]?.events.first?.id == oldest.id else {
      return
    }
    timelines[assistantID]?.prepend(page)
  }

  /// Shows `text` as a message being sent and posts it. Returns whether the text was valid.
  @discardableResult
  func send(text: String, assistantID: Assistant.ID) async -> Bool {
    guard let message = queue(text: text, assistantID: assistantID) else { return false }
    await post(message)
    return true
  }

  /// Adds the message as "Sending…" under a fresh idempotency key, without posting it.
  func queue(text: String, assistantID: Assistant.ID) -> OutgoingMessage? {
    guard TextValidation.isValidMessage(text) else { return nil }
    let message = OutgoingMessage(
      assistantID: assistantID, idempotencyKey: UUIDv7.make(), text: text, createdAt: .now,
      receivedBefore: timelines[assistantID]?.received ?? 0)
    timelines[assistantID, default: Timeline()].outgoing.append(message)
    return message
  }

  /// Posts a queued message. Any error leaves it as "Not Delivered".
  func post(_ message: OutgoingMessage) async {
    let session = session
    do {
      let event = try await client().sendMessage(
        assistantID: message.assistantID, text: message.text,
        idempotencyKey: message.idempotencyKey)
      guard self.session == session else { return }
      if timelines[message.assistantID, default: Timeline()].store(event) {
        setLatestEvent(event, onlyIfLatest: false)
      }
    } catch {
      guard self.session == session else { return }
      setState(.failed, of: message, from: .sending)
    }
  }

  func retry(_ message: OutgoingMessage) async {
    guard setState(.sending, of: message, from: .failed) else { return }
    await post(message)
  }

  func cancel(_ message: OutgoingMessage) {
    timelines[message.assistantID]?.outgoing.removeAll {
      $0.id == message.id && $0.state == .failed
    }
  }

  /// The Assistant's newest message if it failed and was never stored, for the Assistants list.
  func failedLatestMessage(assistantID: Assistant.ID) -> OutgoingMessage? {
    guard let timeline = timelines[assistantID], let message = timeline.outgoing.last,
      message.state == .failed
    else { return nil }
    return timeline.received > message.receivedBefore ? nil : message
  }

  func caption(forMessageID id: String, assistantID: Assistant.ID) -> MessageCaption? {
    timelines[assistantID]?.caption(forMessageID: id)
  }

  @discardableResult
  private func setState(
    _ state: OutgoingMessage.State, of message: OutgoingMessage,
    from current: OutgoingMessage.State
  ) -> Bool {
    guard
      let index = timelines[message.assistantID]?.outgoing.firstIndex(where: {
        $0.id == message.id && $0.state == current
      })
    else { return false }
    timelines[message.assistantID]?.outgoing[index].state = state
    return true
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
    timelines = [:]
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
    let api = try await client()
    let link = try await api.createLink(assistantID: assistantID)
    if let index = assistants.firstIndex(where: { $0.id == assistantID }) {
      assistants[index].links.append(link)
    }
    // The service adds a link_created event that the live connection may not deliver.
    try? await loadLatest(assistantID: assistantID, using: api)
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

  private func loadLatest(assistantID: Assistant.ID, using api: APIClient) async throws {
    let session = session
    let page = try await api.events(assistantID: assistantID, limit: Self.pageSize)
    guard self.session == session else { return }
    let previous = timelines[assistantID]
    var timeline = previous ?? Timeline()
    timeline.refetch(with: page)
    keepUnsentMessages(of: previous, in: &timeline)
    timelines[assistantID] = timeline
    if let latest = timeline.events.last {
      setLatestEvent(latest, onlyIfLatest: false)
    }
  }

  /// Local messages the service hasn't stored survive a refetch that replaces the events.
  private func keepUnsentMessages(of previous: Timeline?, in timeline: inout Timeline) {
    let stored = Set(timeline.events.compactMap(\.idempotencyKey))
    timeline.outgoing = (previous?.outgoing ?? []).filter { !stored.contains($0.idempotencyKey) }
  }

  private func setLatestEvent(_ event: Event, onlyIfLatest: Bool) {
    guard let index = assistants.firstIndex(where: { $0.id == event.assistantID }),
      !onlyIfLatest || assistants[index].latestEvent?.id == event.id
    else { return }
    assistants[index].latestEvent = event
  }

  private func client() async throws -> APIClient {
    if let api { return api }
    let api = try await connect()
    self.api = api
    return api
  }
}
