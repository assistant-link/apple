import AVFoundation
import Foundation
import Observation

enum SpeechEvent: Equatable, Sendable {
  case partial(String)
  case final(String)
  /// The recognizer ended without a final result, for example after a long silence.
  case stopped
  /// The recognizer ended with an error other than silence or a cancel.
  case failed
  /// The microphone input level, 0 to 1.
  case level(Float)
}

/// Joins the recognizer's results into one text: after a pause it may start a new segment whose
/// words no longer include the earlier ones.
enum SpeechSegments {
  /// A revision of the partial result keeps its first word, or at least the words after it, which
  /// the recognizer may rewrite ("two friends" to "to friends later"). Otherwise it started over.
  /// It may also put words before the earlier ones ("the cool one" to "I think the cool one").
  /// A one-word partial only counts as started over when the next one is longer. Punctuation and
  /// case do not count, as a revision often adds them.
  static func startsNew(_ words: String, after provisional: String) -> Bool {
    let old = letters(of: provisional)
    let new = letters(of: words)
    guard let oldFirst = old.first, let newFirst = new.first, oldFirst != newFirst else {
      return false
    }
    let oldTail = old.dropFirst()
    let newTail = new.dropFirst()
    if oldTail.isEmpty { return !newTail.isEmpty }
    return !newTail.starts(with: oldTail) && !contains(new, old)
  }

  /// The final result of a recognition that started new segments holds either only the last one
  /// or, on some systems, all of them again.
  static func final(_ words: String, after earlier: String) -> String {
    let earlierLetters = letters(of: earlier)
    if !earlierLetters.isEmpty, letters(of: words).starts(with: earlierLetters) {
      return join("", words)
    }
    return join(earlier, words)
  }

  static func join(_ first: String, _ second: String) -> String {
    let second = second.trimmingCharacters(in: .whitespacesAndNewlines)
    if first.isEmpty { return second }
    return second.isEmpty ? first : first + " " + second
  }

  private static func letters(of text: String) -> [String] {
    text.split(whereSeparator: \.isWhitespace).map {
      String($0.filter { $0.isLetter || $0.isNumber }).lowercased()
    }
  }

  private static func contains(_ words: [String], _ part: [String]) -> Bool {
    guard words.count >= part.count else { return false }
    return (0...(words.count - part.count)).contains {
      words[$0..<($0 + part.count)].elementsEqual(part)
    }
  }
}

@MainActor
protocol SpeechListener: AnyObject {
  /// Words the recognizer should expect, such as names it would otherwise mishear.
  var vocabulary: [String] { get set }
  func start(_ handler: @escaping @MainActor (SpeechEvent) -> Void) throws
  /// Stops the microphone but lets the recognizer finish what it heard, so the handler still gets
  /// its final result, which often revises the last words. `stop()` ends it.
  func finish()
  /// Stops at once; nothing more reaches the handler.
  func stop()
}

@MainActor
protocol SpeechSpeaker: AnyObject {
  /// Speaks `text`, then calls `onFinish`, unless `stop()` ends it first.
  func speak(_ text: String, onFinish: @escaping @MainActor () -> Void)
  func stop()
  /// Called as a call starts, so the speaker can pick up a changed setting and get ready.
  func prepareForCall()
}

extension SpeechSpeaker {
  func prepareForCall() {}
}

@MainActor
protocol VoiceAudio: AnyObject {
  /// Asks for the microphone and speech recognition permissions; whether both are granted.
  func requestPermission() async -> Bool
  func activate() throws
  /// Plays through the loudspeaker, or else the receiver; a headset takes the sound either way.
  func setSpeaker(_ on: Bool)
  /// Calls `handler` when the audio route changed in a way that affects the microphone, for
  /// example a Bluetooth headset connecting or disconnecting. Ends with `deactivate()`.
  func observeRouteChanges(_ handler: @escaping @MainActor () -> Void)
  func deactivate()
}

extension VoiceAudio {
  func setSpeaker(_ on: Bool) {}
}

@MainActor
protocol SilenceTimer: AnyObject {
  /// Calls `fire` after the silence, unless `restart` or `cancel` comes first.
  func restart(_ fire: @escaping @MainActor () -> Void)
  func cancel()
}

@MainActor
final class TaskSilenceTimer: SilenceTimer {
  private let duration: Duration
  private var task: Task<Void, Never>?

  init(after duration: Duration) {
    self.duration = duration
  }

  func restart(_ fire: @escaping @MainActor () -> Void) {
    task?.cancel()
    task = Task { [duration] in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else { return }
      fire()
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }
}

enum VoiceChat {
  static func text(seconds: Int?) -> String {
    guard let seconds else { return "Voice chat" }
    return "Voice chat · \(duration(seconds: seconds))"
  }

  /// Minutes and seconds, `mm:ss`; minutes keep counting past an hour.
  static func duration(seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }

  static func accessibilityLabel(seconds: Int?) -> String {
    guard let seconds else { return "Voice chat" }
    let length = Duration.seconds(seconds).formatted(
      .units(allowed: [.minutes, .seconds], width: .wide))
    return "Voice chat, \(length)"
  }
}

/// An Assistant's reply being read out in a call.
enum ReplySpeech: Equatable, Sendable {
  case started(Event.ID, text: String, at: Date)
  /// It was read out to the end or cut off.
  case finished(Event.ID, at: Date)
}

/// A hands-free conversation with one Assistant: it listens for the whole call, sends what the
/// user says, and speaks the Assistant's replies. It never listens while speaking, so it can't
/// hear itself, and it never speaks while the user is talking: a reply waits for the end of their
/// turn. Speech is sent whether or not the Assistant is online: the service keeps it until the
/// Assistant connects.
@MainActor
@Observable
final class VoiceCall {
  enum State: Equatable {
    case idle
    /// Listening like `listening`, while the Assistant is not online yet.
    case connecting
    case listening
    case speaking
  }

  private(set) var state = State.idle
  private(set) var isMuted = false
  private(set) var isSpeakerOn = true
  private(set) var assistantID: Assistant.ID?
  /// The microphone input level, 0 to 1, while listening or connecting.
  private(set) var level: Float = 0
  /// Listening gave up after repeated recognizer failures and hears nothing until it tries again.
  private(set) var listeningFailed = false
  /// The words of the utterance in progress.
  var heard: String { SpeechSegments.join(earlierSegments, segment) }
  /// What was said in this call: the user's sent utterances and the replies spoken so far.
  private(set) var transcript: [TranscriptLine] = []
  private(set) var startedAt: Date?

  /// Why the last `start` failed; nil when it started, or did not because a call was running. A
  /// call that started here can still fail to start on the service, which ends it.
  enum StartFailure: Equatable {
    case permissionDenied
    /// The audio session or the recognizer could not start.
    case unavailable
  }

  private(set) var startFailure: StartFailure?

  static let maxFailures = 3

  /// How long after the last new word an utterance ends. Pauses between the sentences of one
  /// thought often reach two seconds, which 1.5 s still split; much longer and the reply feels
  /// slow to start.
  static let endOfUtterance = Duration.milliseconds(2500)

  /// How long to wait for the final result after the microphone stops. The recognizer usually
  /// gives it within a second; without it, the last partial result is taken.
  static let finalResultWait = Duration.milliseconds(1500)

  /// Names the user says often in a call, which the recognizer gets wrong without a hint, for
  /// example "Grok" as "crockpot".
  static let knownNames = ["Grok", "Grok Bot", "Assistant Link"]

  static func vocabulary(assistantName: String?) -> [String] {
    var seen: Set<String> = []
    return ([assistantName].compactMap { $0 } + knownNames)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
  }

  private let listener: any SpeechListener
  private let speaker: any SpeechSpeaker
  private let audio: any VoiceAudio
  private let silence: any SilenceTimer
  /// Spaces out restarts of a recognition that heard nothing, so a failing recognizer can't spin.
  private let retry: any SilenceTimer
  /// Tries listening again after it gave up, because the recognizer often fails at first on a
  /// fresh install (its on-device model still loading) and recovers a little later.
  private let patience: any SilenceTimer
  private let finalResult: any SilenceTimer
  private let notifications: NotificationCenter
  private var interruptionObserver: (any NSObjectProtocol)?
  /// The system holds the audio session, so nothing may listen or speak until it gives it back.
  private var isInterrupted = false
  private var send: (@MainActor (String, Date) -> Void)?
  private var onSpeech: (@MainActor (ReplySpeech) -> Void)?
  private var onEnd: (@MainActor () -> Void)?
  private var isOnline = false
  private var isStarting = false
  /// The utterance ended and the recognizer is finishing it.
  private var isFinishing = false
  private var failures = 0
  /// The utterance in progress before the recognizer last started over.
  private var earlierSegments = ""
  /// The recognizer's latest result since it last started over.
  private var segment = ""
  /// When the first word of the utterance in progress was heard.
  private var utteranceStartedAt: Date?
  /// The reply being read out.
  private var speakingReplyID: Event.ID?
  private var replies: [TranscriptLine] = []
  private var spokenIDs: Set<Event.ID> = []

  init(
    listener: any SpeechListener, speaker: any SpeechSpeaker, audio: any VoiceAudio,
    silence: any SilenceTimer = TaskSilenceTimer(after: VoiceCall.endOfUtterance),
    retry: any SilenceTimer = TaskSilenceTimer(after: .milliseconds(500)),
    patience: any SilenceTimer = TaskSilenceTimer(after: .seconds(5)),
    finalResult: any SilenceTimer = TaskSilenceTimer(after: VoiceCall.finalResultWait),
    notifications: NotificationCenter = .default
  ) {
    self.listener = listener
    self.speaker = speaker
    self.audio = audio
    self.silence = silence
    self.retry = retry
    self.patience = patience
    self.finalResult = finalResult
    self.notifications = notifications
  }

  /// Starts the call after asking for permission. Returns whether it started; only then
  /// `onEnd` runs, once, when the call ends, unless the call ended elsewhere. `send` gets each
  /// utterance with when its first word was heard.
  func start(
    assistantID: Assistant.ID, assistantName: String? = nil, isOnline: Bool,
    send: @escaping @MainActor (String, Date) -> Void,
    onSpeech: @escaping @MainActor (ReplySpeech) -> Void = { _ in },
    onEnd: @escaping @MainActor () -> Void
  ) async -> Bool {
    startFailure = nil
    guard state == .idle, !isStarting else { return false }
    isStarting = true
    defer { isStarting = false }
    guard await audio.requestPermission() else {
      startFailure = .permissionDenied
      return false
    }
    guard state == .idle else { return false }
    isSpeakerOn = true
    audio.setSpeaker(true)
    do {
      try audio.activate()
    } catch {
      startFailure = .unavailable
      return false
    }
    audio.observeRouteChanges { [weak self] in self?.routeChanged() }
    speaker.prepareForCall()
    self.assistantID = assistantID
    self.send = send
    self.onSpeech = onSpeech
    self.isOnline = isOnline
    listener.vocabulary = Self.vocabulary(assistantName: assistantName)
    isMuted = false
    listeningFailed = false
    failures = 0
    transcript = []
    startedAt = .now
    state = isOnline ? .listening : .connecting
    startListening()
    guard state != .idle else {
      startFailure = .unavailable
      return false
    }
    self.onEnd = onEnd
    observeInterruptions()
    return true
  }

  /// Follows whether the Assistant is online, which only decides between `connecting` and
  /// `listening`; the microphone and any utterance in progress are left alone.
  func setOnline(_ online: Bool) {
    isOnline = online
    if online, state == .connecting {
      state = .listening
    } else if !online, state == .listening {
      state = .connecting
    }
  }

  func end() {
    guard state != .idle else { return }
    flushUtterance()
    stopListening()
    speaker.stop()
    finishReply()
    audio.deactivate()
    stopObservingInterruptions()
    replies = []
    spokenIDs = []
    transcript = []
    startedAt = nil
    send = nil
    onSpeech = nil
    isMuted = false
    listeningFailed = false
    state = .idle
    let onEnd = onEnd
    self.onEnd = nil
    onEnd?()
  }

  /// Tries listening again right away after it gave up.
  func retryListening() {
    guard listeningFailed, !isMuted, state != .speaking else { return }
    patience.cancel()
    listeningFailed = false
    failures = 0
    if replies.isEmpty {
      startListening()
    } else {
      speakNext()
    }
  }

  func setMuted(_ muted: Bool) {
    guard state != .idle, muted != isMuted else { return }
    isMuted = muted
    if muted {
      flushUtterance()
      stopListening()
      speakHeldReplies()
    } else {
      listeningFailed = false
      failures = 0
      startListening()
    }
  }

  /// Moving the sound changes the route under the recognizer, so listening restarts as it does
  /// for a headset.
  func setSpeaker(_ on: Bool) {
    guard state != .idle, on != isSpeakerOn else { return }
    isSpeakerOn = on
    audio.setSpeaker(on)
    routeChanged()
  }

  /// Ends the call without `onEnd`, because the service already has the end, or never had the
  /// call when it failed to start there.
  func endedElsewhere(startFailure: StartFailure? = nil) {
    guard state != .idle else { return }
    onEnd = nil
    end()
    self.startFailure = startFailure
  }

  /// Queues a new text message of the Assistant to be spoken. A `call_ended` of the Assistant
  /// ends the call without `onEnd`: the service already has the end.
  func receive(_ event: Event) {
    if state != .idle, event.assistantID == assistantID, event.type == .callEnded,
      event.sender == .assistant
    {
      endedElsewhere()
      return
    }
    guard state != .idle, event.assistantID == assistantID, event.type == .textMessage,
      event.sender == .assistant, !event.deleted,
      let text = event.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
      spokenIDs.insert(event.id).inserted
    else { return }
    replies.append(TranscriptLine(id: event.id, text: text, isFromUser: false))
    if state != .speaking, !isInterrupted, !isUserTalking {
      speakNext()
    }
  }

  private var isUserTalking: Bool { isFinishing || !Self.words(of: heard).isEmpty }

  /// Plays the replies that waited for the user's turn, which just ended.
  @discardableResult
  private func speakHeldReplies() -> Bool {
    guard !replies.isEmpty, state != .speaking, !isInterrupted else { return false }
    speakNext()
    return true
  }

  private func speakNext() {
    guard !replies.isEmpty else {
      state = isOnline ? .listening : .connecting
      listeningFailed = false
      failures = 0
      startListening()
      return
    }
    stopListening()
    state = .speaking
    let reply = replies.removeFirst()
    transcript.append(reply)
    speakingReplyID = reply.id
    onSpeech?(.started(reply.id, text: reply.text, at: .now))
    speaker.speak(reply.text) { [weak self] in
      guard let self, state == .speaking else { return }
      finishReply()
      speakNext()
    }
  }

  private func finishReply() {
    guard let id = speakingReplyID else { return }
    speakingReplyID = nil
    onSpeech?(.finished(id, at: .now))
  }

  /// The microphone moved to another device, which stops the audio engine under the recognizer.
  /// Listening starts again on the new route; the call, mute and speech in progress stay as they are.
  private func routeChanged() {
    guard canHear else { return }
    flushUtterance()
    stopListening()
    if speakHeldReplies() { return }
    retry.restart { [weak self] in self?.resumeListening() }
  }

  /// Like `startListening`, but a failure, likely while the route is still settling, is retried
  /// instead of ending the call.
  private func resumeListening() {
    guard canHear else { return }
    do {
      try listener.start { [weak self] in self?.handle($0) }
    } catch {
      failures += 1
      scheduleRestart()
    }
  }

  private var canHear: Bool {
    (state == .listening || state == .connecting) && !isMuted && !listeningFailed
      && !isInterrupted
  }

  private func observeInterruptions() {
    isInterrupted = false
    interruptionObserver = notifications.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] notification in
      let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
        .flatMap(AVAudioSession.InterruptionType.init)
      let options = AVAudioSession.InterruptionOptions(
        rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
      MainActor.assumeIsolated {
        switch type {
        case .began: self?.interruptionBegan()
        case .ended: self?.interruptionEnded(shouldResume: options.contains(.shouldResume))
        default: break
        }
      }
    }
  }

  private func stopObservingInterruptions() {
    if let interruptionObserver {
      notifications.removeObserver(interruptionObserver)
    }
    interruptionObserver = nil
    isInterrupted = false
  }

  /// Pauses without a restart: the engine and recognizer die with the session, and the system
  /// cuts speech off, so what remains queued waits for the end of the interruption.
  private func interruptionBegan() {
    guard state != .idle, !isInterrupted else { return }
    isInterrupted = true
    flushUtterance()
    stopListening()
    if state == .speaking {
      speaker.stop()
      finishReply()
      state = isOnline ? .listening : .connecting
    }
  }

  /// Without `shouldResume` the system doesn't say whether the user is done with the other
  /// audio, so the user decides, through the same retry as a failed recognizer.
  private func interruptionEnded(shouldResume: Bool) {
    guard state != .idle, isInterrupted else { return }
    isInterrupted = false
    guard shouldResume else {
      listeningFailed = !isMuted
      return
    }
    do {
      try audio.activate()
    } catch {
      listeningFailed = !isMuted
      return
    }
    speakNext()
  }

  private func startListening() {
    guard canHear else { return }
    do {
      try listener.start { [weak self] in self?.handle($0) }
    } catch {
      end()
    }
  }

  private func stopListening() {
    silence.cancel()
    retry.cancel()
    patience.cancel()
    finalResult.cancel()
    isFinishing = false
    earlierSegments = ""
    segment = ""
    utteranceStartedAt = nil
    level = 0
    listener.stop()
  }

  private func handle(_ event: SpeechEvent) {
    guard canHear else { return }
    switch event {
    case .level(let value):
      level = value
    case .partial(let text):
      let isNew = Self.words(of: text) != Self.words(of: segment)
      if SpeechSegments.startsNew(text, after: segment) { earlierSegments = heard }
      segment = text
      if utteranceStartedAt == nil, !Self.words(of: text).isEmpty { utteranceStartedAt = .now }
      if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        failures = 0
      }
      // The recognizer keeps refining what it heard after the user stops, which isn't speech.
      if isNew, !isFinishing { restartSilenceTimer() }
    case .final(let text):
      segment = SpeechSegments.final(text, after: earlierSegments)
      earlierSegments = ""
      finishUtterance()
    case .stopped:
      failures = 0
      finishUtterance()
    case .failed:
      failures += 1
      finishUtterance()
    }
  }

  /// Ignores the case and punctuation, which the recognizer revises as it refines a result.
  static func words(of text: String) -> [Substring] {
    text.lowercased().split { !$0.isLetter && !$0.isNumber }
  }

  private func restartSilenceTimer() {
    silence.restart { [weak self] in self?.awaitFinalResult() }
  }

  private func awaitFinalResult() {
    isFinishing = true
    finalResult.restart { [weak self] in self?.finishUtterance() }
    listener.finish()
  }

  /// Sends what was heard so far, which muting, a route change or the end of the call would
  /// otherwise drop.
  @discardableResult
  private func flushUtterance() -> Bool {
    let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
    let startedAt = utteranceStartedAt ?? .now
    earlierSegments = ""
    segment = ""
    utteranceStartedAt = nil
    guard !text.isEmpty else { return false }
    send?(text, startedAt)
    transcript.append(TranscriptLine(id: UUID().uuidString, text: text, isFromUser: true))
    return true
  }

  private func finishUtterance() {
    let sent = flushUtterance()
    stopListening()
    if speakHeldReplies() { return }
    if sent {
      failures = 0
      startListening()
    } else {
      scheduleRestart()
    }
  }

  private func scheduleRestart() {
    if failures >= Self.maxFailures {
      listeningFailed = true
      patience.restart { [weak self] in
        guard let self else { return }
        listeningFailed = false
        failures = Self.maxFailures - 1
        startListening()
      }
    } else {
      retry.restart { [weak self] in self?.startListening() }
    }
  }
}
