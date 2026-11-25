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
  private(set) var assistants: [Assistant] = [] {
    didSet { enableNotificationsOncePaired() }
  }
  /// The conversations opened so far, by Assistant.
  private(set) var timelines: [Assistant.ID: Timeline] = [:]
  /// The spoken turns of the calls loaded or heard of so far, by call, in the order saved.
  private(set) var callTranscripts: [String: [CallTranscriptEntry]] = [:]
  /// Changes whenever the app starts using an account, so live updates restart with it.
  private(set) var session = 0
  let voiceCall: VoiceCall
  /// The reply voice `start()` gets ready, shared with the speaker of `voiceCall`.
  let kokoro: KokoroVoice?
  /// Shared by the composers, which SwiftUI creates again whenever a screen refreshes.
  let dictation: Dictation
  /// The conversation on top of the navigation stack, whose pushes need no banner.
  @ObservationIgnored private(set) var conversationOnScreen: Assistant.ID?
  private(set) var pushTokenUpload: Task<Void, Never>?

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
  /// The posts of the call that is on or last was.
  private var currentCall: CallPosts?
  /// Keeps the process running until the task finishes, so posts started when the app leaves the
  /// foreground are not cut off by suspension.
  private let keepRunning: @MainActor (Task<Void, Never>) -> Void
  private let enableNotifications: @MainActor () -> Void
  private var hasEnabledNotifications = false
  /// The device's APNs token in hex, uploaded for each account the app uses.
  private var pushToken: String?
  /// The conversation a tapped push asked for, until the Assistants list opens it.
  private var requestedConversation: Assistant.ID?

  init(
    connect: @escaping @Sendable () async throws -> APIClient,
    forget: @escaping @Sendable () throws -> Void = {},
    liveUpdates: @escaping @MainActor (APIClient) -> LiveUpdates? = LiveUpdates.live,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    voiceCall: VoiceCall = .live(),
    dictation: Dictation = .live(),
    kokoro: KokoroVoice? = nil,
    keepRunning: @escaping @MainActor (Task<Void, Never>) -> Void = { _ in },
    enableNotifications: @escaping @MainActor () -> Void = {}
  ) {
    self.keepRunning = keepRunning
    self.enableNotifications = enableNotifications
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
      keepRunning: BackgroundTime.keepRunning, enableNotifications: PushNotifications.enable)
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
      uploadPushToken()
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

  /// From a call, so unlike `prepareReplyVoice()` it prepares Kokoro where Core ML crashes too.
  func retryReplyVoice() {
    kokoro?.retry()
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
      onLinkActivity: { apply($0) },
      onAssistantUpdated: { apply($0) },
      onEventCreated: { apply(created: $0) },
      onEventUpdated: { apply(updated: $0) },
      onTranscriptEntry: { apply($0) })
    if let stop {
      Self.logger.notice("Live updates stopped: \(String(describing: stop), privacy: .public)")
    }
  }

  func apply(_ change: LinkStatusChange) {
    let index = updateLink(id: change.linkID) { link in
      link.status = change.status
      link.lastActiveAt = change.lastActiveAt ?? link.lastActiveAt
      if change.status != .online { link.activity = nil }
    }
    guard let index else { return }
    assistants[index].status = Assistant.Status(links: assistants[index].links.map(\.status))
    syncVoiceCall()
  }

  func apply(_ change: LinkActivityChange) {
    // The service also sends a clear after every agent message and disconnect.
    guard link(id: change.linkID)?.activity != change.activity else { return }
    updateLink(id: change.linkID) { $0.activity = change.activity }
  }

  func apply(_ change: AssistantChange) {
    guard let index = assistants.firstIndex(where: { $0.id == change.id }) else { return }
    assistants[index].name = change.name
    assistants[index].platform = change.platform
  }

  func apply(created event: Event) {
    // The service clears it too, but this way the reply takes the indicator's place at once.
    if event.sender == .assistant, event.type == .textMessage, let linkID = event.linkID {
      updateLink(id: linkID) { $0.activity = nil }
    }
    timelines[event.assistantID]?.receive(event)
    setLatestEvent(event, onlyIfLatest: false)
    voiceCall.receive(event)
    endCallIfEnded(by: event)
  }

  func apply(updated event: Event) {
    timelines[event.assistantID]?.update(event)
    setLatestEvent(event, onlyIfLatest: true)
    endCallIfEnded(by: event)
  }

  func apply(_ entry: CallTranscriptEntry) {
    var entries = callTranscripts[entry.callID] ?? []
    entries.removeAll { $0.id == entry.id }
    entries.append(entry)
    callTranscripts[entry.callID] = entries.sorted { $0.seq < $1.seq }
  }

  /// Fetches the spoken turns of an ended call for its transcript sheet. Turns heard of live
  /// meanwhile are kept.
  func loadTranscript(assistantID: Assistant.ID, callID: String) async throws {
    for entry in try await client().transcript(assistantID: assistantID, callID: callID) {
      apply(entry)
    }
  }

  /// The service ended the call that is on, for example because the Assistant hung up, so
  /// nothing posts its end again.
  private func endCallIfEnded(by event: Event) {
    guard event.type == .voiceCall, let call = event.voiceCall, call.endedAt != nil,
      let callID = currentCall?.callID, call.callID == callID,
      voiceCall.assistantID == event.assistantID
    else { return }
    voiceCall.endedElsewhere()
  }

  private func link(id: Link.ID) -> Link? {
    assistants.lazy.flatMap(\.links).first { $0.id == id }
  }

  /// Returns the index of the Link's Assistant, or `nil` for an unknown Link.
  @discardableResult
  private func updateLink(id: Link.ID, _ update: (inout Link) -> Void) -> Int? {
    for index in assistants.indices {
      if let linkIndex = assistants[index].links.firstIndex(where: { $0.id == id }) {
        update(&assistants[index].links[linkIndex])
        return index
      }
    }
    return nil
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

  /// Loads earlier pages until the event `id` is loaded, for a reply's quote to scroll to it.
  /// Returns whether it is.
  func loadEarlier(untilEventID id: String, assistantID: Assistant.ID) async -> Bool {
    while let timeline = timelines[assistantID] {
      if timeline.events.contains(where: { $0.id == id }) { return true }
      guard timeline.hasMore, let oldest = timeline.events.first,
        (try? await loadEarlier(assistantID: assistantID)) != nil,
        timelines[assistantID]?.events.first?.id != oldest.id
      else { return false }
    }
    return false
  }

  /// Shows `text` as a message being sent and posts it. Returns whether the text was valid.
  @discardableResult
  func send(
    text: String, assistantID: Assistant.ID, via: Event.Via? = nil, replyTo: String? = nil
  ) async -> Bool {
    guard let message = queue(text: text, assistantID: assistantID, via: via, replyTo: replyTo)
    else {
      return false
    }
    await post(message)
    return true
  }

  /// Adds the message as "Sending…" under a fresh idempotency key, without posting it.
  func queue(
    text: String, assistantID: Assistant.ID, via: Event.Via? = nil, replyTo: String? = nil
  ) -> OutgoingMessage? {
    guard TextValidation.isValidMessage(text) else { return nil }
    let message = OutgoingMessage(
      assistantID: assistantID, idempotencyKey: UUIDv7.make(), text: text, createdAt: .now,
      receivedBefore: timelines[assistantID]?.received ?? 0, via: via, replyTo: replyTo)
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
          idempotencyKey: message.idempotencyKey, via: message.via, replyTo: message.replyTo)
      }
      guard self.session == session else { return }
      store(event)
    } catch {
      guard self.session == session else { return }
      setState(.failed, of: message, from: .sending)
    }
  }

  /// Starts a voice chat with the Assistant. The service is told when the chat starts and
  /// ends, which wakes and releases the agent. It keeps the chat as a call with its own
  /// transcript; a service from before calls were sessions gets call events and the user's
  /// speech as messages instead.
  func startVoiceCall(assistantID: Assistant.ID) async -> Bool {
    let call = CallPosts(assistantID: assistantID)
    let started = await voiceCall.start(
      assistantID: assistantID, assistantName: assistant(id: assistantID)?.name,
      isOnline: assistant(id: assistantID)?.status == .online,
      send: { text, startedAt in self.enqueueUtterance(text, startedAt: startedAt, in: call) },
      onSpeech: { self.enqueueReplySpeech($0, in: call) },
      onEnd: { self.enqueueEnd(of: call) })
    if started {
      currentCall = call
      enqueueStart(of: call)
    }
    return started
  }

  /// Speech can come before the Assistant is online, so it stays behind the start. Only a
  /// service without calls falls back to call events: after any other failure the service may
  /// have started the call anyway, and the chat must not be written twice. Such a call could
  /// save nothing and would never wake the agent, so it ends here, and the call the service may
  /// have started under the sent id is ended there.
  private func enqueueStart(of call: CallPosts) {
    let id = UUIDv7.make()
    enqueue {
      do {
        let started = try await self.retrying(attempts: Self.callEventAttempts, in: nil) {
          try await self.client().startCall(id: id, assistantID: call.assistantID)
        }
        call.callID = started.id
      } catch let error as APIError where error.status == 404 {
        call.usesCallEvents = true
        await self.postCallEvent(.callStarted, assistantID: call.assistantID)
      } catch {
        Self.logger.notice("Call start failed: \(error.localizedDescription, privacy: .public)")
        if self.currentCall === call {
          self.voiceCall.endedElsewhere(startFailure: .service)
        }
        await self.postEnd(assistantID: call.assistantID, callID: id)
      }
    }
  }

  private func enqueueUtterance(_ text: String, startedAt: Date, in call: CallPosts) {
    let endedAt = Date.now
    let session = session
    enqueue {
      guard let callID = call.callID else {
        guard call.usesCallEvents, self.session == session,
          let message = self.queue(text: text, assistantID: call.assistantID, via: .voice)
        else { return }
        await self.post(message, attempts: Self.callEventAttempts)
        return
      }
      let id = UUIDv7.make()
      _ = await self.saveEntry {
        try await $0.saveTranscriptEntry(
          id: id, assistantID: call.assistantID, callID: callID, speaker: .user, text: text,
          startedAt: startedAt, endedAt: endedAt)
      }
    }
  }

  /// A reply is saved as it starts to be read out, and ends when the reading does. Without a
  /// session the reply is already in the chat as the Assistant's message.
  private func enqueueReplySpeech(_ speech: ReplySpeech, in call: CallPosts) {
    enqueue {
      guard let callID = call.callID else { return }
      switch speech {
      case .started(let replyID, let text, let startedAt):
        let id = UUIDv7.make()
        let entry = await self.saveEntry {
          try await $0.saveTranscriptEntry(
            id: id, assistantID: call.assistantID, callID: callID, speaker: .assistant,
            text: text, startedAt: startedAt, endedAt: nil)
        }
        if let entry { call.replyEntries[replyID] = entry.id }
      case .finished(let replyID, let endedAt):
        guard let entryID = call.replyEntries.removeValue(forKey: replyID) else { return }
        _ = await self.saveEntry {
          try await $0.updateTranscriptEntry(
            assistantID: call.assistantID, callID: callID, entryID: entryID, endedAt: endedAt)
        }
      }
    }
  }

  /// Keeps trying like the call's other posts; a turn that never goes out is only missing from
  /// the transcript.
  private func saveEntry<T>(_ operation: (APIClient) async throws -> T) async -> T? {
    do {
      return try await retrying(attempts: Self.callEventAttempts, in: nil) {
        try await operation(self.client())
      }
    } catch {
      Self.logger.notice(
        "Transcript entry not saved: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  private func enqueueEnd(of call: CallPosts) {
    enqueue {
      guard let callID = call.callID else {
        if call.usesCallEvents {
          await self.postCallEvent(.callEnded, assistantID: call.assistantID)
        }
        return
      }
      await self.postEnd(assistantID: call.assistantID, callID: callID)
    }
  }

  private func postEnd(assistantID: Assistant.ID, callID: String) async {
    do {
      try await retrying(attempts: Self.callEventAttempts, in: nil) {
        try await self.client().endCall(assistantID: assistantID, callID: callID)
      }
    } catch {
      Self.logger.notice("Call end failed: \(error.localizedDescription, privacy: .public)")
    }
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

  /// A conversation under Details is not on screen. A call outlives the screens pushed on top
  /// of its conversation, such as Details, and ends once the conversation is no longer in the
  /// stack.
  func navigated(to path: [Route]) {
    if case .conversation(let id) = path.last {
      conversationOnScreen = id
    } else {
      conversationOnScreen = nil
    }
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
  private func postCallEvent(_ type: Event.Kind, assistantID: Assistant.ID) async {
    let key = UUIDv7.make()
    do {
      let event = try await retrying(attempts: Self.callEventAttempts, in: nil) {
        try await self.client().sendCallEvent(
          assistantID: assistantID, type: type, idempotencyKey: key)
      }
      store(event)
    } catch {}
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
        guard attempt < attempts, !Task.isCancelled, session == nil || self.session == session,
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
    // A retrying upload would put the token back on the account it is leaving.
    pushTokenUpload?.cancel()
    await pushTokenUpload?.value
    pushTokenUpload = nil
    // The service keeps a deleted account's devices for a while, so the token leaves first.
    try? await client().deletePushToken()
    do {
      try await client().deleteAccount()
    } catch APIError.service(status: 401, code: _, message: _) {
      // The service no longer accepts this credential, so its account is already gone.
    } catch {
      uploadPushToken()
      throw error
    }
    try forget()
    api = nil
    assistants = []
    timelines = [:]
    callTranscripts = [:]
    pairingCodes = [:]
    requestedConversation = nil
    await start()
  }

  /// APNs hands the token over at each launch once notifications are allowed, and again when it
  /// changes.
  func received(pushToken token: Data) {
    pushToken = PushNotifications.hex(token)
    uploadPushToken()
  }

  /// Without an account yet, `start()` uploads the token once it has one.
  private func uploadPushToken() {
    guard let api, let pushToken else { return }
    let session = session
    pushTokenUpload?.cancel()
    pushTokenUpload = Task {
      do {
        try await retrying(attempts: Self.callEventAttempts, in: session) {
          try await api.setPushToken(pushToken)
        }
      } catch {
        Self.logger.notice(
          "Push token upload failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// The permission prompt waits for a paired Link, when there are messages to be notified of.
  /// Afterwards the system answers without asking, so each launch registers with APNs again.
  private func enableNotificationsOncePaired() {
    guard !hasEnabledNotifications, assistants.contains(where: \.hasPairedLink) else { return }
    hasEnabledNotifications = true
    enableNotifications()
  }

  /// A push for the conversation on screen shows no banner: its message is already in view.
  func showsBanner(for push: Push) -> Bool {
    guard let id = push.assistantID else { return true }
    return id != conversationOnScreen
  }

  func open(_ push: Push) {
    if let id = push.assistantID { requestedConversation = id }
  }

  /// The conversation a tapped push asked for, once the Assistants have loaded and include it.
  var conversationToOpen: Assistant.ID? {
    guard phase == .ready, let id = requestedConversation, assistant(id: id) != nil else {
      return nil
    }
    return id
  }

  /// Returns `conversationToOpen` and forgets the request, so it opens once.
  func takeConversationToOpen() -> Assistant.ID? {
    guard let id = conversationToOpen else { return nil }
    requestedConversation = nil
    return id
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
    // The update that ended the call may have come while the live connection was closed.
    for event in timeline.events where event.type == .voiceCall {
      endCallIfEnded(by: event)
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

/// The posts of one voice chat, which go out one after another through the call outbox.
@MainActor
private final class CallPosts {
  let assistantID: Assistant.ID
  /// Set once the service started the call; `nil` while it starts, if it failed to, and for a
  /// service from before calls were sessions.
  var callID: String?
  /// Whether the service is from before calls were sessions.
  var usesCallEvents = false
  /// The transcript entry of each reply being read out, by the reply's event id.
  var replyEntries: [Event.ID: String] = [:]

  init(assistantID: Assistant.ID) {
    self.assistantID = assistantID
  }
}
