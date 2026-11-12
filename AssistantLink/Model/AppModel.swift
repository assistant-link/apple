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
  let voiceCall: VoiceCall
  /// The reply voice `start()` gets ready, shared with the speaker of `voiceCall`.
  let kokoro: KokoroVoice?
  /// Shared by the composers, which SwiftUI creates again whenever a screen refreshes.
  let dictation: Dictation

  /// How often a call's posts are tried. With `Backoff` this keeps trying for a few minutes.
  static let callEventAttempts = 12
  private static let pageSize = 50
  private static let logger = Logger(subsystem: "ai.assistantlink.app", category: "live")

  private let connect: @Sendable () async throws -> APIClient
  private let forget: @Sendable () throws -> Void
  private let makeLiveUpdates: @MainActor (APIClient) -> LiveUpdates?
  private var api: APIClient?
  private var pairingCodes: [Link.ID: PairingCode] = [:]
  private let sleep: @Sendable (Duration) async throws -> Void
  /// The tail of a call's posts, which run one after another so the Assistant sees them in the
  /// order they happened.
  private(set) var callOutbox: Task<Void, Never>?
  /// Keeps the process running until the task finishes, so posts started when the app leaves the
  /// foreground are not cut off by suspension.
  private let keepRunning: @MainActor (Task<Void, Never>) -> Void

  init(
    connect: @escaping @Sendable () async throws -> APIClient,
    forget: @escaping @Sendable () throws -> Void = {},
    liveUpdates: @escaping @MainActor (APIClient) -> LiveUpdates? = LiveUpdates.live,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    voiceCall: VoiceCall = .live(),
    dictation: Dictation = .live(),
    kokoro: KokoroVoice? = nil,
    keepRunning: @escaping @MainActor (Task<Void, Never>) -> Void = { _ in }
  ) {
    self.keepRunning = keepRunning
    self.connect = connect
    self.forget = forget
    self.makeLiveUpdates = liveUpdates
    self.sleep = sleep
    self.voiceCall = voiceCall
    self.dictation = dictation
    self.kokoro = kokoro
  }

  static func live() -> AppModel {
    let baseURL = ServiceConfiguration.baseURL()
    let store = KeychainCredentialStore(account: baseURL.absoluteString)
    let kokoro = KokoroVoice()
    return AppModel(
      connect: { try await AccountSession.connect(baseURL: baseURL, store: store) },
      forget: { try store.delete() }, voiceCall: .live(kokoro: kokoro), kokoro: kokoro,
      keepRunning: BackgroundTime.keepRunning)
  }

  static func preview(
    _ assistants: [Assistant], timelines: [Assistant.ID: Timeline] = [:],
    voiceCall: VoiceCall = .live()
  ) -> AppModel {
    let model = AppModel(connect: { throw APIError.unreachable }, voiceCall: voiceCall)
    model.assistants = assistants
    model.timelines = timelines
    model.phase = .ready
    return model
  }

  func start() async {
    prepareReplyVoice()
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

  /// Returns at once: the download goes on by itself, so the account does not wait for it.
  func prepareReplyVoice() {
    kokoro?.prepare()
  }

  /// Best effort: the Assistants wake in the background, so a failure is only logged.
  func wake() async {
    guard let api, api.credential != nil else { return }
    do {
      try await api.wake()
    } catch {
      Self.logger.notice("Wake failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  func refresh() async throws {
    assistants = try await client().listAssistants()
    syncVoiceCall()
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
        syncVoiceCall()
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
      assistants[index].status = Assistant.Status(links: assistants[index].links.map(\.status))
      syncVoiceCall()
      return
    }
  }

  func apply(created event: Event) {
    timelines[event.assistantID]?.receive(event)
    setLatestEvent(event, onlyIfLatest: false)
    voiceCall.receive(event)
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
  func send(text: String, assistantID: Assistant.ID, via: Event.Via? = nil) async -> Bool {
    guard let message = queue(text: text, assistantID: assistantID, via: via) else {
      return false
    }
    await post(message)
    return true
  }

  /// Adds the message as "Sending…" under a fresh idempotency key, without posting it.
  func queue(text: String, assistantID: Assistant.ID, via: Event.Via? = nil) -> OutgoingMessage? {
    guard TextValidation.isValidMessage(text) else { return nil }
    let message = OutgoingMessage(
      assistantID: assistantID, idempotencyKey: UUIDv7.make(), text: text, createdAt: .now,
      receivedBefore: timelines[assistantID]?.received ?? 0, via: via)
    timelines[assistantID, default: Timeline()].outgoing.append(message)
    return message
  }

  /// Posts a queued message, trying up to `attempts` times while the failure may pass. Failing
  /// for good leaves it as "Not Delivered".
  func post(_ message: OutgoingMessage, attempts: Int = 1) async {
    let session = session
    do {
      let event = try await retrying(attempts: attempts, in: session) {
        try await self.client().sendMessage(
          assistantID: message.assistantID, text: message.text,
          idempotencyKey: message.idempotencyKey, via: message.via)
      }
      guard self.session == session else { return }
      store(event)
    } catch {
      guard self.session == session else { return }
      setState(.failed, of: message, from: .sending)
    }
  }

  /// Starts a voice chat with the Assistant; what the user says is sent as messages. The
  /// service is told when the chat starts and ends, which wakes and releases the agent.
  func startVoiceCall(assistantID: Assistant.ID) async -> Bool {
    let started = await voiceCall.start(
      assistantID: assistantID, assistantName: assistant(id: assistantID)?.name,
      isOnline: assistant(id: assistantID)?.status == .online,
      send: { text in
        // Speech can come before the Assistant is online, so keep it behind `call_started`.
        guard let message = self.queue(text: text, assistantID: assistantID, via: .voice) else {
          return
        }
        let session = self.session
        self.enqueue {
          if self.session == session {
            await self.post(message, attempts: Self.callEventAttempts)
          }
        }
      },
      onEnd: { self.enqueueCallEvent(.callEnded, assistantID: assistantID) })
    if started {
      enqueueCallEvent(.callStarted, assistantID: assistantID)
    }
    return started
  }

  func endVoiceCall() {
    voiceCall.end()
  }

  /// The app can be suspended or killed from here on, and the user never taps End, so the call
  /// ends now and its posts get background time to go out.
  func leftForeground() {
    guard voiceCall.state != .idle else { return }
    endVoiceCall()
    if let callOutbox { keepRunning(callOutbox) }
  }

  /// A call outlives the screens pushed on top of its conversation, such as Details, and ends
  /// once the conversation is no longer in the stack.
  func navigated(to path: [Route]) {
    guard let id = voiceCall.assistantID, !path.contains(.conversation(id)) else { return }
    endVoiceCall()
  }

  private func enqueue(_ work: @escaping @MainActor () async -> Void) {
    let previous = callOutbox
    callOutbox = Task {
      await previous?.value
      await work()
    }
  }

  /// Keeps trying while the failure may pass, because an Assistant that never sees the end of
  /// a call keeps its agent awake. A call's later posts wait behind it, so it gives up eventually.
  /// It outlives a session change, such as reconnecting, because only the account owns the call.
  private func enqueueCallEvent(_ type: Event.Kind, assistantID: Assistant.ID) {
    let key = UUIDv7.make()
    enqueue {
      do {
        let event = try await self.retrying(attempts: Self.callEventAttempts, in: nil) {
          try await self.client().sendCallEvent(
            assistantID: assistantID, type: type, idempotencyKey: key)
        }
        self.store(event)
      } catch {}
    }
  }

  /// Runs `operation` again after a capped backoff while its failure is transient, and throws
  /// the last error once `attempts` are used up or, given a `session`, that session ended.
  private func retrying<T>(
    attempts: Int, in session: Int?, _ operation: () async throws -> T
  ) async throws -> T {
    var backoff = Backoff()
    var attempt = 1
    while true {
      do {
        return try await operation()
      } catch {
        guard attempt < attempts, session == nil || self.session == session,
          (error as? APIError)?.isTransient ?? true
        else { throw error }
        try await sleep(backoff.next())
        attempt += 1
      }
    }
  }

  private func store(_ event: Event) {
    if timelines[event.assistantID, default: Timeline()].store(event) {
      setLatestEvent(event, onlyIfLatest: false)
    }
  }

  private func syncVoiceCall() {
    guard let id = voiceCall.assistantID else { return }
    voiceCall.setOnline(assistant(id: id)?.status == .online)
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
    // The account owns the call, so the Assistant hears the end before the account is gone.
    endVoiceCall()
    await callOutbox?.value
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

  /// The service sends no event when a Link pairs, so this turns true when the app learns the
  /// Link's new status: from the live connection once the agent connects, or from a refresh.
  func isPaired(linkID: Link.ID) -> Bool {
    assistants.lazy.flatMap(\.links).first { $0.id == linkID }?.isPaired ?? false
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
