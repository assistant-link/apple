import Foundation
import Synchronization
import Testing

@testable import AssistantLink

@MainActor
private final class FakeListener: SpeechListener {
  private(set) var isListening = false
  private(set) var starts = 0
  var startError: (any Error)?
  private var handler: (@MainActor (SpeechEvent) -> Void)?

  func start(_ handler: @escaping @MainActor (SpeechEvent) -> Void) throws {
    if let startError { throw startError }
    starts += 1
    isListening = true
    self.handler = handler
  }

  func stop() {
    isListening = false
    handler = nil
  }

  func hear(_ event: SpeechEvent) { handler?(event) }
}

@MainActor
private final class FakeSpeaker: SpeechSpeaker {
  private(set) var spoken: [String] = []
  private(set) var isSpeaking = false
  private(set) var stops = 0
  private var onFinish: (@MainActor () -> Void)?

  func speak(_ text: String, onFinish: @escaping @MainActor () -> Void) {
    spoken.append(text)
    isSpeaking = true
    self.onFinish = onFinish
  }

  func stop() {
    stops += 1
    isSpeaking = false
    onFinish = nil
  }

  func finish() {
    isSpeaking = false
    onFinish?()
  }
}

@MainActor
private final class FakeAudio: VoiceAudio {
  var isAllowed = true
  var activateError: (any Error)?
  private(set) var isActive = false

  func requestPermission() async -> Bool { isAllowed }

  func activate() throws {
    if let activateError { throw activateError }
    isActive = true
  }

  func deactivate() { isActive = false }
}

@MainActor
private final class Setup {
  let listener = FakeListener()
  let speaker = FakeSpeaker()
  let audio = FakeAudio()
  var sent: [String] = []
  private(set) var ends = 0
  private(set) var call: VoiceCall!

  init() {
    call = VoiceCall(
      listener: listener, speaker: speaker, audio: audio, silence: .milliseconds(30))
  }

  func start(isOnline: Bool = true) async {
    let started = await call.start(
      assistantID: "as-1", isOnline: isOnline, send: { [unowned self] in sent.append($0) },
      onEnd: { [unowned self] in ends += 1 })
    #expect(started)
  }

  func assistantMessage(_ id: String, _ text: String?, assistantID: String = "as-1") -> Event {
    Event(
      id: id, assistantID: assistantID, type: .textMessage, sender: .assistant,
      createdAt: .now, text: text)
  }

  func noteEnd() { ends += 1 }

  func waitForSilence() async throws {
    try await Task.sleep(for: .milliseconds(200))
  }
}

@MainActor
struct VoiceCallStateTests {
  @Test func startsListeningWithTheAudioSessionActive() async {
    let setup = Setup()
    #expect(setup.call.state == .idle)

    await setup.start()

    #expect(setup.call.state == .listening)
    #expect(setup.call.assistantID == "as-1")
    #expect(setup.listener.isListening)
    #expect(setup.audio.isActive)
  }

  @Test func anOfflineAssistantKeepsTheCallConnectingUntilItIsOnline() async {
    let setup = Setup()
    await setup.start(isOnline: false)

    #expect(setup.call.state == .connecting)
    #expect(!setup.listener.isListening)
    #expect(setup.audio.isActive)

    setup.call.setOnline(true)

    #expect(setup.call.state == .listening)
    #expect(setup.listener.isListening)
  }

  @Test func theAssistantGoingOfflineMidCallGoesBackToConnecting() async {
    let setup = Setup()
    await setup.start()
    setup.listener.hear(.partial("Hello"))

    setup.call.setOnline(false)

    #expect(setup.call.state == .connecting)
    #expect(!setup.listener.isListening)
    #expect(setup.sent.isEmpty)

    setup.call.setOnline(true)

    #expect(setup.call.state == .listening)
    #expect(setup.listener.isListening)
  }

  @Test func aReplyBeingSpokenIsFinishedBeforeConnectingAgain() async {
    let setup = Setup()
    await setup.start()
    setup.call.receive(setup.assistantMessage("e-1", "Bye"))

    setup.call.setOnline(false)
    #expect(setup.call.state == .speaking)

    setup.speaker.finish()
    #expect(setup.call.state == .connecting)
    #expect(!setup.listener.isListening)
  }

  @Test func aReplyWhileConnectingIsSpoken() async {
    let setup = Setup()
    await setup.start(isOnline: false)

    setup.call.receive(setup.assistantMessage("e-1", "Hi"))

    #expect(setup.speaker.spoken == ["Hi"])
  }

  @Test func deniedPermissionDoesNotStart() async {
    let setup = Setup()
    setup.audio.isAllowed = false

    let started = await setup.call.start(
      assistantID: "as-1", isOnline: true, send: { _ in }, onEnd: {})

    #expect(!started)
    #expect(setup.call.state == .idle)
    #expect(!setup.listener.isListening)
    #expect(!setup.audio.isActive)
  }

  @Test func aFailingAudioSessionDoesNotStart() async {
    let setup = Setup()
    setup.audio.activateError = URLError(.unknown)

    let started = await setup.call.start(
      assistantID: "as-1", isOnline: true, send: { _ in }, onEnd: {})

    #expect(!started)
    #expect(setup.call.state == .idle)
  }

  @Test func aListenerThatCannotStartEndsTheCall() async {
    let setup = Setup()
    setup.listener.startError = URLError(.unknown)

    let started = await setup.call.start(
      assistantID: "as-1", isOnline: true, send: { _ in }, onEnd: {})

    #expect(!started)
    #expect(setup.call.state == .idle)
    #expect(!setup.audio.isActive)
  }

  @Test func aReplyStopsListeningAndTheEndOfItResumes() async {
    let setup = Setup()
    await setup.start()

    setup.call.receive(setup.assistantMessage("e-1", "Hello"))

    #expect(setup.call.state == .speaking)
    #expect(!setup.listener.isListening)
    #expect(setup.speaker.spoken == ["Hello"])

    setup.speaker.finish()

    #expect(setup.call.state == .listening)
    #expect(setup.listener.isListening)
  }

  @Test func muteStopsListeningAndUnmuteResumes() async {
    let setup = Setup()
    await setup.start()

    setup.call.setMuted(true)

    #expect(setup.call.isMuted)
    #expect(setup.call.state == .listening)
    #expect(!setup.listener.isListening)

    setup.call.setMuted(false)

    #expect(!setup.call.isMuted)
    #expect(setup.listener.isListening)
  }

  @Test func mutedCallsStillSpeakButDoNotListenAfterwards() async {
    let setup = Setup()
    await setup.start()
    setup.call.setMuted(true)

    setup.call.receive(setup.assistantMessage("e-1", "Hello"))
    #expect(setup.speaker.spoken == ["Hello"])
    setup.speaker.finish()

    #expect(setup.call.state == .listening)
    #expect(!setup.listener.isListening)
  }

  @Test func endingWhileSpeakingStopsSpeechAndClearsTheQueue() async {
    let setup = Setup()
    await setup.start()
    setup.call.receive(setup.assistantMessage("e-1", "One"))
    setup.call.receive(setup.assistantMessage("e-2", "Two"))

    setup.call.end()

    #expect(setup.call.state == .idle)
    #expect(!setup.speaker.isSpeaking)
    #expect(!setup.listener.isListening)
    #expect(!setup.audio.isActive)

    setup.speaker.finish()
    #expect(setup.call.state == .idle)
    #expect(setup.speaker.spoken == ["One"])
  }

  @Test func endingWhileMutedResetsTheMute() async {
    let setup = Setup()
    await setup.start()
    setup.call.setMuted(true)

    setup.call.end()
    await setup.start()

    #expect(!setup.call.isMuted)
    #expect(setup.listener.isListening)
  }

  @Test func endingAnIdleCallDoesNothing() {
    let setup = Setup()

    setup.call.end()

    #expect(setup.speaker.stops == 0)
    #expect(setup.ends == 0)
  }

  @Test func endingTwiceReportsTheEndOnce() async {
    let setup = Setup()
    await setup.start()

    setup.call.end()
    setup.call.end()

    #expect(setup.ends == 1)
  }

  @Test func aCallThatCannotStartReportsNoEnd() async {
    let setup = Setup()
    setup.listener.startError = URLError(.unknown)

    _ = await setup.call.start(
      assistantID: "as-1", isOnline: true, send: { _ in }, onEnd: { setup.noteEnd() })

    #expect(setup.ends == 0)
  }

  @Test func theMicrophoneLevelIsKeptWhileListening() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.level(0.4))
    #expect(setup.call.level == 0.4)

    setup.call.setMuted(true)
    #expect(setup.call.level == 0)
  }
}

@MainActor
struct VoiceCallUtteranceTests {
  @Test func anUtteranceIsSentAfterTheSilenceAndListeningRestarts() async throws {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("remind me"))
    #expect(setup.sent.isEmpty)
    setup.listener.hear(.partial("remind me to call David"))
    try await setup.waitForSilence()

    #expect(setup.sent == ["remind me to call David"])
    #expect(setup.listener.isListening)
    #expect(setup.listener.starts == 2)
  }

  @Test func newPartialResultsPostponeTheEndOfTheUtterance() async throws {
    let setup = Setup()
    await setup.start()

    for words in ["a", "a b", "a b c"] {
      setup.listener.hear(.partial(words))
      try await Task.sleep(for: .milliseconds(15))
    }
    #expect(setup.sent.isEmpty)

    try await setup.waitForSilence()
    #expect(setup.sent == ["a b c"])
  }

  @Test func aFinalResultEndsTheUtteranceAtOnce() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.final("  Hello there \n"))

    #expect(setup.sent == ["Hello there"])
    #expect(setup.listener.starts == 2)
  }

  @Test func recognitionStoppingOnItsOwnSendsWhatWasHeardAndRestarts() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("Hello"))
    setup.listener.hear(.stopped)

    #expect(setup.sent == ["Hello"])
    #expect(setup.listener.starts == 2)
  }

  @Test(arguments: ["", "   ", "\n\t"])
  func emptyUtterancesAreNotSent(text: String) async throws {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial(text))
    try await setup.waitForSilence()
    setup.listener.hear(.final(text))

    #expect(setup.sent.isEmpty)
    #expect(setup.listener.isListening)
  }

  @Test func muteDropsTheUtteranceInProgress() async throws {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("Hello"))
    setup.call.setMuted(true)
    try await setup.waitForSilence()

    #expect(setup.sent.isEmpty)
  }

  @Test func aReplyDropsTheUtteranceInProgress() async throws {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("Hello"))
    setup.call.receive(setup.assistantMessage("e-1", "Hi"))
    try await setup.waitForSilence()

    #expect(setup.sent.isEmpty)
  }

  @Test func endingCancelsTheSilenceTimer() async throws {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("Hello"))
    setup.call.end()
    try await setup.waitForSilence()

    #expect(setup.sent.isEmpty)
  }
}

@MainActor
struct VoiceCallSpeechQueueTests {
  @Test func repliesAreSpokenOneAtATimeInOrder() async {
    let setup = Setup()
    await setup.start()

    setup.call.receive(setup.assistantMessage("e-1", "One"))
    setup.call.receive(setup.assistantMessage("e-2", "Two"))
    setup.call.receive(setup.assistantMessage("e-3", "Three"))

    #expect(setup.speaker.spoken == ["One"])
    setup.speaker.finish()
    #expect(setup.speaker.spoken == ["One", "Two"])
    #expect(setup.call.state == .speaking)
    #expect(!setup.listener.isListening)
    setup.speaker.finish()
    setup.speaker.finish()

    #expect(setup.speaker.spoken == ["One", "Two", "Three"])
    #expect(setup.call.state == .listening)
    #expect(setup.listener.isListening)
  }

  @Test func onlyTextMessagesOfTheAssistantWithTextAreSpoken() async {
    let setup = Setup()
    await setup.start()
    let user = Event(
      id: "e-1", assistantID: "as-1", type: .textMessage, sender: .user, createdAt: .now,
      text: "Mine")
    let link = Event(
      id: "e-2", assistantID: "as-1", type: .linkCreated, sender: .system, createdAt: .now)

    setup.call.receive(user)
    setup.call.receive(link)
    setup.call.receive(setup.assistantMessage("e-3", nil))
    setup.call.receive(setup.assistantMessage("e-4", "  "))
    setup.call.receive(setup.assistantMessage("e-5", "Other", assistantID: "as-2"))

    #expect(setup.speaker.spoken.isEmpty)
    #expect(setup.call.state == .listening)
  }

  @Test func repliesWithoutACallAreNotSpoken() {
    let setup = Setup()

    setup.call.receive(setup.assistantMessage("e-1", "Hello"))

    #expect(setup.speaker.spoken.isEmpty)
  }

  @Test func anEventSeenTwiceIsSpokenOnce() async {
    let setup = Setup()
    await setup.start()

    setup.call.receive(setup.assistantMessage("e-1", "Hello"))
    setup.speaker.finish()
    setup.call.receive(setup.assistantMessage("e-1", "Hello"))

    #expect(setup.speaker.spoken == ["Hello"])
  }
}

struct VoiceDurationTests {
  @Test(arguments: [(0, "00:00"), (59, "00:59"), (151, "02:31"), (3665, "61:05")])
  func theBubbleShowsMinutesAndSeconds(seconds: Int, time: String) {
    #expect(VoiceChat.text(seconds: seconds) == "Voice chat · \(time)")
  }

  @Test func withoutADurationTheBubbleSaysVoiceChat() {
    #expect(VoiceChat.text(seconds: nil) == "Voice chat")
  }
}

struct VoiceChatTimelineTests {
  private func call(_ id: String, _ type: Event.Kind, at seconds: Double) -> Event {
    Event(
      id: id, assistantID: "as-1", type: type, sender: .user,
      createdAt: Date(timeIntervalSince1970: 1000 + seconds))
  }

  @Test func theDurationRunsFromTheLatestEarlierStartToTheEnd() {
    let timeline = Timeline(events: [
      call("e-1", .callStarted, at: 0), call("e-2", .callEnded, at: 30),
      call("e-3", .callStarted, at: 100), .stub("e-4"), call("e-5", .callEnded, at: 251.9),
    ])

    #expect(timeline.voiceChatSeconds(endedBy: timeline.events[1]) == 30)
    #expect(timeline.voiceChatSeconds(endedBy: timeline.events[4]) == 151)
  }

  @Test func anEndWithoutALoadedStartHasNoDuration() {
    let timeline = Timeline(events: [call("e-2", .callEnded, at: 30)])

    #expect(timeline.voiceChatSeconds(endedBy: timeline.events[0]) == nil)
  }
}

struct CallEventDecodingTests {
  @Test(arguments: [("call_started", Event.Kind.callStarted), ("call_ended", .callEnded)])
  func decodesACallEventWithoutContent(name: String, kind: Event.Kind) throws {
    let json = Data(
      #"""
      {"id": "e-1", "assistant_id": "as-1", "type": "\#(name)", "sender": "user",
       "link_id": null, "created_at": "2026-10-08T12:30:15Z", "deleted": false,
       "delivery_status": "sent"}
      """#.utf8)

    let event = try APIClient.decoder.decode(Event.self, from: json)

    #expect(event.type == kind)
    #expect(event.text == nil)
  }
}

@MainActor
struct VoiceCallAppModelTests {
  private final class Stub: Sendable {
    let bodies = Mutex<[[String: String]]>([])

    func answer(_ request: URLRequest, _ body: Data?) throws -> (Int, Data) {
      switch (request.httpMethod, request.url?.path()) {
      case ("POST", "/api/v1/assistants/as-1/call_events"):
        let sent = try (body?.jsonObject() ?? [:]).compactMapValues { $0 as? String }
        bodies.withLock { $0.append(sent) }
        let event = """
          {"id": "ev-\(sent["idempotency_key"] ?? "")", "assistant_id": "as-1",
           "type": "\(sent["type"] ?? "")", "sender": "user", "link_id": null,
           "created_at": "2026-10-08T12:30:15Z", "deleted": false, "delivery_status": "sent"}
          """
        return (201, Data(json: #"{"event": \#(event)}"#))
      case ("GET", "/api/v1/assistants"):
        return (200, Data(json: #"{"assistants": [\#(Self.assistant)]}"#))
      default:
        return (404, Data(json: #"{"error": {"code": "not_found", "message": "No."}}"#))
      }
    }

    static let assistant = """
      {"id": "as-1", "name": "Muse", "avatar": "sparkles", "status": "offline", "links": [
       {"id": "l-1", "label": null, "status": "offline", "last_active_at": null}],
       "latest_event": null}
      """
  }

  private func startedModel(_ stub: Stub, listener: FakeListener) async -> AppModel {
    let api = APIClient(
      baseURL: URL(string: "https://service.test")!, credential: "ala_secret",
      session: StubURLProtocol.session { request, body in try stub.answer(request, body) })
    let model = AppModel(
      connect: { api },
      voiceCall: VoiceCall(listener: listener, speaker: FakeSpeaker(), audio: FakeAudio()))
    await model.start()
    return model
  }

  private func settle(_ stub: Stub, calls count: Int) async throws {
    for _ in 0..<100 where stub.bodies.withLock({ $0.count }) < count {
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  @Test func startingSendsCallStartedAndWaitsForTheAssistantToBeOnline() async throws {
    let stub = Stub()
    let listener = FakeListener()
    let model = await startedModel(stub, listener: listener)

    #expect(await model.startVoiceCall(assistantID: "as-1"))
    try await settle(stub, calls: 1)

    let sent = stub.bodies.withLock { $0 }
    #expect(sent.map { $0["type"] } == ["call_started"])
    #expect(UUIDv7.date(fromID: sent[0]["idempotency_key"] ?? "") != nil)
    #expect(model.voiceCall.state == .connecting)
    #expect(!listener.isListening)

    model.apply(LinkStatusChange(linkID: "l-1", status: .online, lastActiveAt: nil))
    #expect(model.voiceCall.state == .listening)
    #expect(listener.isListening)

    model.apply(LinkStatusChange(linkID: "l-1", status: .offline, lastActiveAt: nil))
    #expect(model.voiceCall.state == .connecting)
  }

  @Test func endingSendsCallEndedOnceAfterCallStarted() async throws {
    let stub = Stub()
    let listener = FakeListener()
    let model = await startedModel(stub, listener: listener)
    #expect(await model.startVoiceCall(assistantID: "as-1"))

    model.endVoiceCall()
    model.endVoiceCall()
    try await settle(stub, calls: 2)
    try await Task.sleep(for: .milliseconds(100))

    let sent = stub.bodies.withLock { $0 }
    #expect(sent.map { $0["type"] } == ["call_started", "call_ended"])
    #expect(Set(sent.compactMap { $0["idempotency_key"] }).count == 2)
    #expect(model.voiceCall.state == .idle)
    #expect(!listener.isListening)
  }
}
