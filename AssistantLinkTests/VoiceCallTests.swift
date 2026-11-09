import AVFoundation
import Foundation
import Synchronization
import Testing

@testable import AssistantLink

@MainActor
private final class FakeListener: SpeechListener {
  var vocabulary: [String] = []
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

  func deactivate() {
    isActive = false
    routeHandler = nil
  }

  private var routeHandler: (@MainActor () -> Void)?

  func observeRouteChanges(_ handler: @escaping @MainActor () -> Void) { routeHandler = handler }

  func changeRoute() { routeHandler?() }
}

@MainActor
private final class FakeSilence: SilenceTimer {
  private(set) var restarts = 0
  private var pending: (@MainActor () -> Void)?
  var isPending: Bool { pending != nil }

  func restart(_ fire: @escaping @MainActor () -> Void) {
    restarts += 1
    pending = fire
  }

  func cancel() { pending = nil }

  func fire() {
    let fire = pending
    pending = nil
    fire?()
  }
}

@MainActor
private final class Setup {
  let listener = FakeListener()
  let speaker = FakeSpeaker()
  let audio = FakeAudio()
  let silence = FakeSilence()
  let retry = FakeSilence()
  let patience = FakeSilence()
  let center = NotificationCenter()
  var sent: [String] = []
  private(set) var sentBeforeEnd: [String] = []
  private(set) var ends = 0
  private(set) var call: VoiceCall!

  init() {
    call = VoiceCall(
      listener: listener, speaker: speaker, audio: audio, silence: silence, retry: retry,
      patience: patience, notifications: center)
  }

  func interrupt(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false) {
    var userInfo: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
    if type == .ended {
      let options: AVAudioSession.InterruptionOptions = shouldResume ? .shouldResume : []
      userInfo[AVAudioSessionInterruptionOptionKey] = options.rawValue
    }
    center.post(
      name: AVAudioSession.interruptionNotification, object: nil, userInfo: userInfo)
  }

  func start(isOnline: Bool = true, assistantName: String? = nil) async {
    let started = await call.start(
      assistantID: "as-1", assistantName: assistantName, isOnline: isOnline,
      send: { [unowned self] in sent.append($0) },
      onEnd: { [unowned self] in
        ends += 1
        sentBeforeEnd = sent
      })
    #expect(started)
  }

  func assistantMessage(_ id: String, _ text: String?, assistantID: String = "as-1") -> Event {
    Event(
      id: id, assistantID: assistantID, type: .textMessage, sender: .assistant,
      createdAt: .now, text: text)
  }

  func noteEnd() { ends += 1 }
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

  @Test func theRecognizerExpectsTheAssistantsNameAndKnownNames() async {
    let setup = Setup()
    await setup.start(assistantName: " Nova ")

    #expect(setup.listener.vocabulary == ["Nova", "Grok", "Grok Bot", "Assistant Link"])
  }

  @Test func anAssistantNamedLikeAKnownNameIsExpectedOnce() {
    #expect(VoiceCall.vocabulary(assistantName: "grok") == ["grok", "Grok Bot", "Assistant Link"])
    #expect(VoiceCall.vocabulary(assistantName: nil) == VoiceCall.knownNames)
  }

  @Test func anOfflineAssistantShowsConnectingButTheCallListensAtOnce() async {
    let setup = Setup()
    await setup.start(isOnline: false)

    #expect(setup.call.state == .connecting)
    #expect(setup.listener.isListening)
    #expect(setup.audio.isActive)

    setup.call.setOnline(true)

    #expect(setup.call.state == .listening)
    #expect(setup.listener.isListening)
    #expect(setup.listener.starts == 1)
  }

  @Test func theAssistantGoingOfflineMidCallKeepsListeningAndTheUtterance() async {
    let setup = Setup()
    await setup.start()
    setup.listener.hear(.partial("Hello"))

    setup.call.setOnline(false)

    #expect(setup.call.state == .connecting)
    #expect(setup.listener.isListening)
    #expect(setup.listener.starts == 1)
    #expect(setup.sent.isEmpty)

    setup.silence.fire()

    #expect(setup.sent == ["Hello"])

    setup.call.setOnline(true)

    #expect(setup.call.state == .listening)
    #expect(setup.listener.isListening)
  }

  @Test func aReplyBeingSpokenIsFinishedBeforeListeningAgainWhileOffline() async {
    let setup = Setup()
    await setup.start()
    setup.call.receive(setup.assistantMessage("e-1", "Bye"))

    setup.call.setOnline(false)
    #expect(setup.call.state == .speaking)

    setup.speaker.finish()
    #expect(setup.call.state == .connecting)
    #expect(setup.listener.isListening)
  }

  @Test func aReplyWhileConnectingIsSpoken() async {
    let setup = Setup()
    await setup.start(isOnline: false)

    setup.call.receive(setup.assistantMessage("e-1", "Hi"))

    #expect(setup.speaker.spoken == ["Hi"])
  }

  @Test func aRouteChangeRestartsListeningOnTheNewRouteAndKeepsTheCall() async {
    let setup = Setup()
    await setup.start()
    setup.listener.hear(.partial("Hello"))

    setup.audio.changeRoute()

    #expect(setup.sent == ["Hello"])
    #expect(!setup.listener.isListening)
    #expect(setup.call.state == .listening)

    setup.retry.fire()

    #expect(setup.listener.isListening)
    #expect(setup.listener.starts == 2)
    #expect(setup.ends == 0)
  }

  @Test func aRouteChangeWhileMutedStaysMuted() async {
    let setup = Setup()
    await setup.start()
    setup.call.setMuted(true)

    setup.audio.changeRoute()
    setup.retry.fire()

    #expect(!setup.listener.isListening)
    #expect(setup.call.isMuted)
    #expect(setup.call.state == .listening)
  }

  @Test func aRouteChangeWhileSpeakingDoesNotInterruptOrListen() async {
    let setup = Setup()
    await setup.start()
    setup.call.receive(setup.assistantMessage("e-1", "Hi"))

    setup.audio.changeRoute()
    setup.retry.fire()

    #expect(setup.call.state == .speaking)
    #expect(setup.speaker.isSpeaking)
    #expect(!setup.listener.isListening)

    setup.speaker.finish()
    #expect(setup.listener.isListening)
  }

  @Test func aRouteStillSettlingRetriesInsteadOfEndingTheCall() async {
    let setup = Setup()
    await setup.start()
    setup.listener.startError = SpeechListenerError.recognizerUnavailable

    setup.audio.changeRoute()
    setup.retry.fire()

    #expect(setup.call.state == .listening)
    #expect(setup.ends == 0)
    #expect(setup.retry.isPending)

    setup.listener.startError = nil
    setup.retry.fire()
    #expect(setup.listener.isListening)
  }

  @Test func muteDuringARouteChangeDoesNotResumeListening() async {
    let setup = Setup()
    await setup.start()
    setup.audio.changeRoute()

    setup.call.setMuted(true)
    setup.retry.fire()

    #expect(!setup.listener.isListening)
  }

  @Test func routeChangesAfterTheCallEndedAreIgnored() async {
    let setup = Setup()
    await setup.start()
    setup.call.end()

    setup.audio.changeRoute()
    setup.retry.fire()

    #expect(!setup.listener.isListening)
    #expect(setup.listener.starts == 1)
  }

  @Test func onlyDeviceChangesAffectTheMicrophone() {
    #expect(LiveVoiceAudio.affectsMicrophone(.newDeviceAvailable))
    #expect(LiveVoiceAudio.affectsMicrophone(.oldDeviceUnavailable))
    #expect(!LiveVoiceAudio.affectsMicrophone(.categoryChange))
    #expect(!LiveVoiceAudio.affectsMicrophone(.wakeFromSleep))
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
    #expect(setup.call.startFailure == .permissionDenied)
  }

  @Test func aFailingAudioSessionDoesNotStart() async {
    let setup = Setup()
    setup.audio.activateError = URLError(.unknown)

    let started = await setup.call.start(
      assistantID: "as-1", isOnline: true, send: { _ in }, onEnd: {})

    #expect(!started)
    #expect(setup.call.state == .idle)
    #expect(setup.call.startFailure == .unavailable)
  }

  @Test func aStartThatWorksHasNoFailure() async {
    let setup = Setup()
    setup.audio.isAllowed = false
    _ = await setup.call.start(assistantID: "as-1", isOnline: true, send: { _ in }, onEnd: {})
    setup.audio.isAllowed = true

    await setup.start()

    #expect(setup.call.startFailure == nil)
  }

  @Test func aListenerThatCannotStartEndsTheCall() async {
    let setup = Setup()
    setup.listener.startError = URLError(.unknown)

    let started = await setup.call.start(
      assistantID: "as-1", isOnline: true, send: { _ in }, onEnd: {})

    #expect(!started)
    #expect(setup.call.state == .idle)
    #expect(!setup.audio.isActive)
    #expect(setup.call.startFailure == .unavailable)
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

  @Test func theWaveformFollowsTheMicrophoneWhileConnecting() async {
    let setup = Setup()
    await setup.start(isOnline: false)
    #expect(setup.call.state == .connecting)

    setup.listener.hear(.level(0.6))
    #expect(setup.call.amplitude == Double(Float(0.6)))

    setup.call.setMuted(true)
    #expect(setup.call.amplitude == 0)
  }
}

@MainActor
struct VoiceCallRecognizerErrorTests {
  @Test func anEndWithNothingHeardRestartsOnlyAfterAPause() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.stopped)

    #expect(!setup.listener.isListening)
    #expect(setup.retry.isPending)
    setup.retry.fire()
    #expect(setup.listener.isListening)
    #expect(setup.listener.starts == 2)
  }

  @Test func anUtteranceThatWasHeardRestartsAtOnce() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("Hello"))
    setup.listener.hear(.failed)

    #expect(setup.sent == ["Hello"])
    #expect(setup.listener.starts == 2)
    #expect(!setup.retry.isPending)
  }

  @Test func repeatedFailuresStopListeningAndShowIt() async {
    let setup = Setup()
    await setup.start()

    for _ in 0..<VoiceCall.maxFailures {
      #expect(setup.call.listeningFailed == false)
      setup.listener.hear(.failed)
      setup.retry.fire()
    }

    #expect(setup.call.listeningFailed)
    #expect(!setup.listener.isListening)
    #expect(!setup.retry.isPending)
    #expect(setup.call.state == .listening)
  }

  @Test func endsWithNothingHeardNeverGiveUp() async {
    let setup = Setup()
    await setup.start()

    for _ in 0..<(VoiceCall.maxFailures * 3) {
      setup.listener.hear(.stopped)
      setup.retry.fire()
    }

    #expect(!setup.call.listeningFailed)
    #expect(setup.listener.isListening)
  }

  @Test func aCallThatGaveUpListeningTriesAgainAfterAWhile() async {
    let setup = Setup()
    await setup.start()
    for _ in 0..<VoiceCall.maxFailures {
      setup.listener.hear(.failed)
      setup.retry.fire()
    }
    #expect(setup.call.listeningFailed)
    #expect(setup.patience.isPending)

    setup.patience.fire()

    #expect(!setup.call.listeningFailed)
    #expect(setup.listener.isListening)
    setup.listener.hear(.partial("Hello"))
    setup.listener.hear(.final("Hello"))
    #expect(setup.sent == ["Hello"])
  }

  @Test func retryingListeningAfterGivingUpRestartsTheRecognizer() async {
    let setup = Setup()
    await setup.start()
    for _ in 0..<VoiceCall.maxFailures {
      setup.listener.hear(.failed)
      setup.retry.fire()
    }

    setup.call.retryListening()

    #expect(!setup.call.listeningFailed)
    #expect(setup.listener.isListening)
    #expect(!setup.patience.isPending)
    setup.listener.hear(.failed)
    #expect(!setup.call.listeningFailed)
  }

  @Test func retryingListeningDoesNothingWhileMutedOrSpeaking() async {
    let setup = Setup()
    await setup.start()
    for _ in 0..<VoiceCall.maxFailures {
      setup.listener.hear(.failed)
      setup.retry.fire()
    }
    setup.call.receive(setup.assistantMessage("e-1", "Hello"))

    setup.call.retryListening()

    #expect(setup.call.state == .speaking)
    #expect(setup.call.listeningFailed)
    #expect(!setup.listener.isListening)
  }

  @Test func retryingListeningDoesNothingWhileListeningWorks() async {
    let setup = Setup()
    await setup.start()
    let starts = setup.listener.starts

    setup.call.retryListening()

    #expect(setup.listener.starts == starts)
  }

  @Test func aRecognizerThatKeepsFailingGivesUpAgainAfterOneFailure() async {
    let setup = Setup()
    await setup.start()
    for _ in 0..<VoiceCall.maxFailures {
      setup.listener.hear(.failed)
      setup.retry.fire()
    }
    setup.patience.fire()

    setup.listener.hear(.failed)

    #expect(setup.call.listeningFailed)
    #expect(setup.patience.isPending)
  }

  @Test func endingAndMutingCancelTheLateRetry() async {
    let setup = Setup()
    await setup.start()
    for _ in 0..<VoiceCall.maxFailures {
      setup.listener.hear(.failed)
      setup.retry.fire()
    }

    setup.call.setMuted(true)
    #expect(!setup.patience.isPending)

    setup.call.setMuted(false)
    for _ in 0..<VoiceCall.maxFailures {
      setup.listener.hear(.failed)
      setup.retry.fire()
    }
    setup.call.end()
    #expect(!setup.patience.isPending)
  }

  @Test func aResultInBetweenResetsTheFailureCount() async {
    let setup = Setup()
    await setup.start()

    for _ in 0..<(VoiceCall.maxFailures - 1) {
      setup.listener.hear(.failed)
      setup.retry.fire()
    }
    setup.listener.hear(.partial("Hi"))
    setup.listener.hear(.final("Hi"))
    for _ in 0..<(VoiceCall.maxFailures - 1) {
      setup.listener.hear(.failed)
      setup.retry.fire()
    }

    #expect(!setup.call.listeningFailed)
    #expect(setup.listener.isListening)
  }

  @Test func aFailedCallTriesListeningAgainAfterAReply() async {
    let setup = Setup()
    await setup.start()
    for _ in 0..<VoiceCall.maxFailures {
      setup.listener.hear(.failed)
      setup.retry.fire()
    }

    setup.call.receive(setup.assistantMessage("e1", "Hello"))
    #expect(setup.speaker.spoken == ["Hello"])
    setup.speaker.finish()

    #expect(!setup.call.listeningFailed)
    #expect(setup.listener.isListening)
  }

  @Test func aBenignEndBetweenFailuresResetsTheCount() async {
    let setup = Setup()
    await setup.start()

    for _ in 0..<VoiceCall.maxFailures {
      setup.listener.hear(.failed)
      setup.retry.fire()
      setup.listener.hear(.stopped)
      setup.retry.fire()
    }

    #expect(!setup.call.listeningFailed)
  }

  @Test func emptyPartialResultsDoNotResetTheCount() async {
    let setup = Setup()
    await setup.start()

    for _ in 0..<VoiceCall.maxFailures {
      setup.listener.hear(.partial(""))
      setup.listener.hear(.failed)
      setup.retry.fire()
    }

    #expect(setup.call.listeningFailed)
  }

  @Test(arguments: ["mute", "reply", "end"])
  func nothingRestartsAfter(action: String) async {
    let setup = Setup()
    await setup.start()
    setup.listener.hear(.stopped)
    let starts = setup.listener.starts

    switch action {
    case "mute": setup.call.setMuted(true)
    case "reply": setup.call.receive(setup.assistantMessage("e1", "Hi"))
    default: setup.call.end()
    }
    setup.retry.fire()

    #expect(setup.listener.starts == starts)
    #expect(!setup.listener.isListening)
  }

  @Test func unmutingTriesListeningAgainAfterAFailure() async {
    let setup = Setup()
    await setup.start()
    for _ in 0..<VoiceCall.maxFailures {
      setup.listener.hear(.failed)
      setup.retry.fire()
    }

    setup.call.setMuted(true)
    setup.call.setMuted(false)

    #expect(!setup.call.listeningFailed)
    #expect(setup.listener.isListening)
  }

  @Test func endingResetsTheFailure() async {
    let setup = Setup()
    await setup.start()
    for _ in 0..<VoiceCall.maxFailures {
      setup.listener.hear(.failed)
      setup.retry.fire()
    }

    setup.call.end()
    await setup.start()

    #expect(!setup.call.listeningFailed)
    #expect(setup.listener.isListening)
  }
}

@MainActor
struct VoiceCallUtteranceTests {
  @Test func anUtteranceIsSentAfterTheSilenceAndListeningRestarts() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("remind me"))
    #expect(setup.sent.isEmpty)
    setup.listener.hear(.partial("remind me to call David"))
    setup.silence.fire()

    #expect(setup.sent == ["remind me to call David"])
    #expect(setup.listener.isListening)
    #expect(setup.listener.starts == 2)
  }

  @Test func newPartialResultsRestartTheSilence() async {
    let setup = Setup()
    await setup.start()

    for words in ["a", "a b", "a b c"] {
      setup.listener.hear(.partial(words))
    }

    #expect(setup.silence.restarts == 3)
    #expect(setup.sent.isEmpty)
  }

  @Test func repeatedPartialResultsDoNotPutOffTheEnd() async {
    let setup = Setup()
    await setup.start()

    for _ in 0..<5 {
      setup.listener.hear(.partial("remind me"))
    }

    #expect(setup.silence.restarts == 1)
  }

  @Test func refiningCaseOrPunctuationDoesNotPutOffTheEndButIsSent() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("remind me to call david"))
    setup.listener.hear(.partial("Remind me to call David."))
    setup.silence.fire()

    #expect(setup.silence.restarts == 1)
    #expect(setup.sent == ["Remind me to call David."])
  }

  @Test func aChangedWordPutsOffTheEnd() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("talking in the crock"))
    setup.listener.hear(.partial("talking in the Grok"))

    #expect(setup.silence.restarts == 2)
  }

  @Test func aFinalResultWinsOverThePendingSilence() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("call David"))
    setup.listener.hear(.final("Call David."))

    #expect(setup.sent == ["Call David."])
    #expect(!setup.silence.isPending)
    setup.silence.fire()
    #expect(setup.sent == ["Call David."])
  }

  @Test func theWordsIgnoreCaseAndPunctuation() {
    #expect(VoiceCall.words(of: "Hello, there!") == VoiceCall.words(of: "hello there"))
    #expect(VoiceCall.words(of: " ... ").isEmpty)
    #expect(VoiceCall.words(of: "it's 5") == ["it", "s", "5"])
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
  func emptyUtterancesAreNotSent(text: String) async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial(text))
    setup.silence.fire()
    setup.retry.fire()
    setup.listener.hear(.final(text))
    setup.retry.fire()

    #expect(setup.sent.isEmpty)
    #expect(setup.listener.isListening)
  }

  @Test func anUtteranceFinishedWhileTheAssistantIsOfflineIsSent() async {
    let setup = Setup()
    await setup.start(isOnline: false)

    setup.listener.hear(.partial("Hello"))
    setup.silence.fire()
    setup.listener.hear(.final("Are you there"))

    #expect(setup.sent == ["Hello", "Are you there"])
    #expect(setup.call.state == .connecting)
    #expect(setup.listener.isListening)
  }

  @Test func muteWhileConnectingStopsAndUnmuteResumesListening() async {
    let setup = Setup()
    await setup.start(isOnline: false)

    setup.call.setMuted(true)
    #expect(!setup.listener.isListening)

    setup.call.setMuted(false)
    #expect(setup.listener.isListening)
  }

  @Test func muteSendsTheUtteranceInProgress() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("Hello"))
    setup.call.setMuted(true)
    setup.silence.fire()

    #expect(setup.sent == ["Hello"])
    #expect(!setup.silence.isPending)
  }

  @Test func muteWithNothingHeardSendsNothing() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("  "))
    setup.call.setMuted(true)

    #expect(setup.sent.isEmpty)
  }

  @Test func aReplySendsTheUtteranceInProgressBeforeSpeaking() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("Hello"))
    setup.call.receive(setup.assistantMessage("e-1", "Hi"))
    setup.silence.fire()

    #expect(setup.sent == ["Hello"])
    #expect(setup.speaker.spoken == ["Hi"])
  }

  @Test func endingSendsTheUtteranceInProgressBeforeTheEnd() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("Hello"))
    setup.call.end()
    setup.silence.fire()

    #expect(setup.sent == ["Hello"])
    #expect(setup.ends == 1)
    #expect(setup.sentBeforeEnd == ["Hello"])
  }

  @Test func endingWithNothingHeardSendsNothing() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("  "))
    setup.call.end()

    #expect(setup.sent.isEmpty)
  }

  @Test func endingCancelsTheSilenceTimer() async {
    let setup = Setup()
    await setup.start()

    setup.listener.hear(.partial("Hello"))
    setup.call.end()

    #expect(!setup.silence.isPending)
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
    /// How many `call_ended` posts still fail with a network error before one succeeds.
    let endFailures = Mutex(0)
    /// How many message posts still fail with a network error before one succeeds.
    let messageFailures = Mutex(0)

    func answer(_ request: URLRequest, _ body: Data?) throws -> (Int, Data) {
      switch (request.httpMethod, request.url?.path()) {
      case ("POST", "/api/v1/assistants/as-1/messages"):
        let sent = try (body?.jsonObject() ?? [:]).compactMapValues { $0 as? String }
        bodies.withLock { $0.append(sent.merging(["type": "message"]) { $1 }) }
        if messageFailures.withLock({ failures in
          guard failures > 0 else { return false }
          failures -= 1
          return true
        }) {
          throw URLError(.notConnectedToInternet)
        }
        let event = """
          {"id": "ev-\(sent["idempotency_key"] ?? "")", "assistant_id": "as-1",
           "type": "text_message", "sender": "user", "link_id": null,
           "created_at": "2026-10-08T12:30:15Z", "deleted": false, "delivery_status": "sent",
           "idempotency_key": "\(sent["idempotency_key"] ?? "")",
           "text_message": {"text": "\(sent["text"] ?? "")"}}
          """
        return (201, Data(json: #"{"message": \#(event)}"#))
      case ("POST", "/api/v1/assistants/as-1/call_events"):
        let sent = try (body?.jsonObject() ?? [:]).compactMapValues { $0 as? String }
        bodies.withLock { $0.append(sent) }
        if sent["type"] == "call_ended",
          endFailures.withLock({ failures in
            guard failures > 0 else { return false }
            failures -= 1
            return true
          })
        {
          throw URLError(.notConnectedToInternet)
        }
        let event = """
          {"id": "ev-\(sent["idempotency_key"] ?? "")", "assistant_id": "as-1",
           "type": "\(sent["type"] ?? "")", "sender": "user", "link_id": null,
           "created_at": "2026-10-08T12:30:15Z", "deleted": false, "delivery_status": "sent"}
          """
        return (201, Data(json: #"{"event": \#(event)}"#))
      case ("GET", "/api/v1/assistants"):
        return (200, Data(json: #"{"assistants": [\#(Self.assistant)]}"#))
      case ("DELETE", "/api/v1/account"):
        bodies.withLock { $0.append(["type": "delete_account"]) }
        return (204, Data())
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

  private func startedModel(
    _ stub: Stub, listener: FakeListener,
    keepRunning: @escaping @MainActor (Task<Void, Never>) -> Void = { _ in }
  ) async -> AppModel {
    let api = APIClient(
      baseURL: URL(string: "https://service.test")!, credential: "ala_secret",
      session: StubURLProtocol.session { request, body in try stub.answer(request, body) })
    let model = AppModel(
      connect: { api }, sleep: { _ in },
      voiceCall: VoiceCall(listener: listener, speaker: FakeSpeaker(), audio: FakeAudio()),
      keepRunning: keepRunning)
    await model.start()
    return model
  }

  @Test func startingSendsCallStartedAndListensWhileTheAssistantIsOffline() async {
    let stub = Stub()
    let listener = FakeListener()
    let model = await startedModel(stub, listener: listener)

    #expect(await model.startVoiceCall(assistantID: "as-1"))
    await model.callOutbox?.value

    let sent = stub.bodies.withLock { $0 }
    #expect(sent.map { $0["type"] } == ["call_started"])
    #expect(UUIDv7.date(fromID: sent[0]["idempotency_key"] ?? "") != nil)
    #expect(model.voiceCall.state == .connecting)
    #expect(listener.isListening)

    model.apply(LinkStatusChange(linkID: "l-1", status: .online, lastActiveAt: nil))
    #expect(model.voiceCall.state == .listening)
    #expect(listener.isListening)

    model.apply(LinkStatusChange(linkID: "l-1", status: .offline, lastActiveAt: nil))
    #expect(model.voiceCall.state == .connecting)
    #expect(listener.isListening)
  }

  @Test func endingSendsCallEndedOnceAfterCallStarted() async {
    let stub = Stub()
    let listener = FakeListener()
    let model = await startedModel(stub, listener: listener)
    #expect(await model.startVoiceCall(assistantID: "as-1"))

    model.endVoiceCall()
    model.endVoiceCall()
    await model.callOutbox?.value

    let sent = stub.bodies.withLock { $0 }
    #expect(sent.map { $0["type"] } == ["call_started", "call_ended"])
    #expect(Set(sent.compactMap { $0["idempotency_key"] }).count == 2)
    #expect(model.voiceCall.state == .idle)
    #expect(!listener.isListening)
  }

  @Test func theUtteranceFlushedByEndingIsSentBeforeCallEnded() async {
    let stub = Stub()
    let listener = FakeListener()
    let model = await startedModel(stub, listener: listener)
    #expect(await model.startVoiceCall(assistantID: "as-1"))

    listener.hear(.partial("Goodbye"))
    model.endVoiceCall()
    await model.callOutbox?.value

    let sent = stub.bodies.withLock { $0 }
    #expect(sent.map { $0["type"] } == ["call_started", "message", "call_ended"])
    #expect(sent[1]["text"] == "Goodbye")
  }

  @Test func leavingTheForegroundEndsTheCallAfterTheLastUtteranceAndKeepsTheAppRunning() async {
    let stub = Stub()
    stub.endFailures.withLock { $0 = 2 }
    let listener = FakeListener()
    var held: [Task<Void, Never>] = []
    let model = await startedModel(stub, listener: listener) { held.append($0) }
    #expect(await model.startVoiceCall(assistantID: "as-1"))

    listener.hear(.partial("Bye"))
    model.leftForeground()

    #expect(model.voiceCall.state == .idle)
    #expect(held.count == 1)
    await held[0].value
    let sent = stub.bodies.withLock { $0 }
    #expect(
      sent.map { $0["type"] }
        == ["call_started", "message", "call_ended", "call_ended", "call_ended"])
  }

  @Test func leavingTheForegroundWithoutACallHoldsNothing() async {
    var held = 0
    let model = await startedModel(Stub(), listener: FakeListener()) { _ in held += 1 }

    model.leftForeground()

    #expect(held == 0)
  }

  @Test func loggingOutEndsTheCallBeforeTheAccountIsDeleted() async throws {
    let stub = Stub()
    let model = await startedModel(stub, listener: FakeListener())
    #expect(await model.startVoiceCall(assistantID: "as-1"))

    try await model.logOut()

    let sent = stub.bodies.withLock { $0 }
    #expect(sent.map { $0["type"] } == ["call_started", "call_ended", "delete_account"])
    #expect(model.voiceCall.state == .idle)
  }

  @Test func callEndedIsRetriedUntilItIsDelivered() async {
    let stub = Stub()
    stub.endFailures.withLock { $0 = 5 }
    let model = await startedModel(stub, listener: FakeListener())
    #expect(await model.startVoiceCall(assistantID: "as-1"))

    model.endVoiceCall()
    await model.callOutbox?.value

    let sent = stub.bodies.withLock { $0 }
    #expect(sent.map { $0["type"] } == ["call_started"] + Array(repeating: "call_ended", count: 6))
    #expect(Set(sent.dropFirst().compactMap { $0["idempotency_key"] }).count == 1)
  }

  @Test func aPendingCallEndedSurvivesASessionChange() async {
    let stub = Stub()
    stub.endFailures.withLock { $0 = 1 }
    let api = APIClient(
      baseURL: URL(string: "https://service.test")!, credential: "ala_secret",
      session: StubURLProtocol.session { request, body in try stub.answer(request, body) })
    let holder = Mutex<AppModel?>(nil)
    let model = AppModel(
      connect: { api }, sleep: { _ in await holder.withLock { $0 }?.start() },
      voiceCall: VoiceCall(listener: FakeListener(), speaker: FakeSpeaker(), audio: FakeAudio()))
    holder.withLock { $0 = model }
    await model.start()
    #expect(await model.startVoiceCall(assistantID: "as-1"))
    let session = model.session

    model.endVoiceCall()
    await model.callOutbox?.value

    #expect(model.session == session + 1)
    let sent = stub.bodies.withLock { $0 }
    #expect(sent.map { $0["type"] } == ["call_started", "call_ended", "call_ended"])
    #expect(Set(sent.dropFirst().compactMap { $0["idempotency_key"] }).count == 1)
    #expect(model.timelines["as-1"]?.events.map(\.type) == [.callEnded])
  }

  @Test func callEndedGivesUpAfterTheAttemptLimitSoLaterPostsAreNotBlocked() async {
    let stub = Stub()
    stub.endFailures.withLock { $0 = 1000 }
    let model = await startedModel(stub, listener: FakeListener())
    #expect(await model.startVoiceCall(assistantID: "as-1"))

    model.endVoiceCall()
    await model.callOutbox?.value

    let ended = stub.bodies.withLock { $0 }.filter { $0["type"] == "call_ended" }
    #expect(ended.count == AppModel.callEventAttempts)
  }

  @Test func aVoiceMessageIsRetriedAndStaysBeforeCallEnded() async {
    let stub = Stub()
    stub.messageFailures.withLock { $0 = 2 }
    let listener = FakeListener()
    let model = await startedModel(stub, listener: listener)
    #expect(await model.startVoiceCall(assistantID: "as-1"))

    listener.hear(.partial("Hello"))
    model.endVoiceCall()
    await model.callOutbox?.value

    let sent = stub.bodies.withLock { $0 }
    #expect(
      sent.map { $0["type"] } == ["call_started", "message", "message", "message", "call_ended"])
    #expect(Set(sent.filter { $0["type"] == "message" }.map { $0["idempotency_key"] }).count == 1)
    #expect(model.timelines["as-1"]?.outgoing.allSatisfy { $0.state != .failed } == true)
  }

  @Test func aVoiceMessageThatNeverGoesOutShowsNotDeliveredAndCallEndedStillGoesOut() async {
    let stub = Stub()
    stub.messageFailures.withLock { $0 = 1000 }
    let listener = FakeListener()
    let model = await startedModel(stub, listener: listener)
    #expect(await model.startVoiceCall(assistantID: "as-1"))

    listener.hear(.partial("Hello"))
    model.endVoiceCall()
    await model.callOutbox?.value

    let sent = stub.bodies.withLock { $0 }
    #expect(sent.filter { $0["type"] == "message" }.count == AppModel.callEventAttempts)
    #expect(sent.last?["type"] == "call_ended")
    #expect(model.timelines["as-1"]?.outgoing.map(\.state) == [.failed])
  }

  @Test func theCallSurvivesOpeningDetails() async {
    let listener = FakeListener()
    let model = await startedModel(Stub(), listener: listener)
    #expect(await model.startVoiceCall(assistantID: "as-1"))

    model.navigated(to: [.conversation("as-1")])
    model.navigated(to: [.conversation("as-1"), .details("as-1")])
    model.navigated(to: [.conversation("as-1")])

    #expect(model.voiceCall.state == .connecting)
    #expect(listener.isListening)
  }

  @Test func theCallEndsWhenItsConversationIsClosed() async {
    let stub = Stub()
    let model = await startedModel(stub, listener: FakeListener())
    #expect(await model.startVoiceCall(assistantID: "as-1"))

    model.navigated(to: [.conversation("as-1"), .details("as-1")])
    model.navigated(to: [])
    await model.callOutbox?.value

    #expect(model.voiceCall.state == .idle)
    #expect(stub.bodies.withLock { $0 }.map { $0["type"] } == ["call_started", "call_ended"])
  }

  @Test func theCallEndsWhenAnotherConversationReplacesIt() async {
    let model = await startedModel(Stub(), listener: FakeListener())
    #expect(await model.startVoiceCall(assistantID: "as-1"))

    model.navigated(to: [.conversation("as-2")])

    #expect(model.voiceCall.state == .idle)
  }
}

@MainActor
struct VoiceCallInterruptionTests {
  @Test func anInterruptionPausesListeningWithoutRestarting() async {
    let setup = Setup()
    await setup.start()
    setup.listener.hear(.partial("hello there"))

    setup.interrupt(.began)

    #expect(!setup.listener.isListening)
    #expect(setup.listener.starts == 1)
    #expect(setup.sent == ["hello there"])
    #expect(setup.call.state == .listening)
    #expect(!setup.call.listeningFailed)
    #expect(!setup.retry.isPending)
    #expect(!setup.patience.isPending)
  }

  @Test func recognizerEventsDuringAnInterruptionDoNotRestartListening() async {
    let setup = Setup()
    await setup.start()
    setup.interrupt(.began)

    setup.listener.hear(.failed)
    setup.retry.fire()
    setup.patience.fire()

    #expect(setup.listener.starts == 1)
    #expect(!setup.listener.isListening)
  }

  @Test func listeningResumesWhenTheInterruptionEndsWithShouldResume() async {
    let setup = Setup()
    await setup.start()
    setup.interrupt(.began)

    setup.interrupt(.ended, shouldResume: true)

    #expect(setup.listener.isListening)
    #expect(setup.listener.starts == 2)
    #expect(setup.audio.isActive)
    #expect(!setup.call.listeningFailed)
  }

  @Test func theBannerShowsWhenTheInterruptionEndsWithoutShouldResume() async {
    let setup = Setup()
    await setup.start()
    setup.interrupt(.began)

    setup.interrupt(.ended)

    #expect(setup.call.listeningFailed)
    #expect(!setup.listener.isListening)
    #expect(!setup.patience.isPending)
    #expect(setup.call.state == .listening)

    setup.call.retryListening()

    #expect(setup.listener.isListening)
    #expect(!setup.call.listeningFailed)
  }

  @Test func theBannerShowsWhenTheAudioSessionCannotBeReactivated() async {
    let setup = Setup()
    await setup.start()
    setup.interrupt(.began)
    setup.audio.activateError = URLError(.unknown)

    setup.interrupt(.ended, shouldResume: true)

    #expect(setup.call.listeningFailed)
    #expect(!setup.listener.isListening)
  }

  @Test func anInterruptionWhileSpeakingKeepsTheRepliesForTheResume() async {
    let setup = Setup()
    await setup.start()
    setup.call.receive(setup.assistantMessage("e1", "first"))
    setup.call.receive(setup.assistantMessage("e2", "second"))
    #expect(setup.call.state == .speaking)

    setup.interrupt(.began)

    #expect(!setup.speaker.isSpeaking)
    #expect(!setup.listener.isListening)

    setup.call.receive(setup.assistantMessage("e3", "third"))
    #expect(setup.speaker.spoken == ["first"])

    setup.interrupt(.ended, shouldResume: true)

    #expect(setup.call.state == .speaking)
    #expect(setup.speaker.spoken == ["first", "second"])
  }

  @Test func anInterruptionKeepsAMutedCallMuted() async {
    let setup = Setup()
    await setup.start()
    setup.call.setMuted(true)

    setup.interrupt(.began)
    setup.interrupt(.ended, shouldResume: true)

    #expect(!setup.listener.isListening)
    #expect(!setup.call.listeningFailed)
  }

  @Test func interruptionsOutsideACallAreIgnored() async {
    let setup = Setup()

    setup.interrupt(.began)
    setup.interrupt(.ended, shouldResume: true)
    await setup.start()
    setup.call.end()
    setup.interrupt(.began)
    setup.interrupt(.ended, shouldResume: true)

    #expect(setup.listener.starts == 1)
    #expect(setup.call.state == .idle)
  }

  @Test func anEndWithoutABeginIsIgnored() async {
    let setup = Setup()
    await setup.start()

    setup.interrupt(.ended)

    #expect(!setup.call.listeningFailed)
    #expect(setup.listener.isListening)
  }
}
