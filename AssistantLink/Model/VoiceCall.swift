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

@MainActor
protocol SpeechListener: AnyObject {
  func start(_ handler: @escaping @MainActor (SpeechEvent) -> Void) throws
  func stop()
}

@MainActor
protocol SpeechSpeaker: AnyObject {
  /// Speaks `text`, then calls `onFinish`, unless `stop()` ends it first.
  func speak(_ text: String, onFinish: @escaping @MainActor () -> Void)
  func stop()
}

@MainActor
protocol VoiceAudio: AnyObject {
  /// Asks for the microphone and speech recognition permissions; whether both are granted.
  func requestPermission() async -> Bool
  func activate() throws
  func deactivate()
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
  /// Minutes and seconds, `mm:ss`; minutes keep counting past an hour.
  static func text(seconds: Int?) -> String {
    guard let seconds else { return "Voice chat" }
    return String(format: "Voice chat · %02d:%02d", seconds / 60, seconds % 60)
  }
}

/// A hands-free conversation with one Assistant: it listens for the whole call, sends what the
/// user says, and speaks the Assistant's replies. It never listens while speaking, so it can't
/// hear itself. Speech is sent whether or not the Assistant is online: the service keeps it until
/// the Assistant connects.
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
  private(set) var assistantID: Assistant.ID?
  /// The microphone input level, 0 to 1, while listening.
  private(set) var level: Float = 0
  /// Listening gave up after repeated recognizer failures; the call goes on but hears nothing.
  private(set) var listeningFailed = false

  static let maxFailures = 3

  private let listener: any SpeechListener
  private let speaker: any SpeechSpeaker
  private let audio: any VoiceAudio
  private let silence: any SilenceTimer
  /// Spaces out restarts of a recognition that heard nothing, so a failing recognizer can't spin.
  private let retry: any SilenceTimer
  private var send: (@MainActor (String) -> Void)?
  private var onEnd: (@MainActor () -> Void)?
  private var isOnline = false
  private var isStarting = false
  private var heard = ""
  private var failures = 0
  private var replies: [String] = []
  private var spokenIDs: Set<Event.ID> = []

  init(
    listener: any SpeechListener, speaker: any SpeechSpeaker, audio: any VoiceAudio,
    silence: any SilenceTimer = TaskSilenceTimer(after: .milliseconds(1200)),
    retry: any SilenceTimer = TaskSilenceTimer(after: .seconds(1))
  ) {
    self.listener = listener
    self.speaker = speaker
    self.audio = audio
    self.silence = silence
    self.retry = retry
  }

  /// Starts the call after asking for permission. Returns whether it started; only then
  /// `onEnd` runs, once, when the call ends.
  func start(
    assistantID: Assistant.ID, isOnline: Bool, send: @escaping @MainActor (String) -> Void,
    onEnd: @escaping @MainActor () -> Void
  ) async -> Bool {
    guard state == .idle, !isStarting else { return false }
    isStarting = true
    defer { isStarting = false }
    guard await audio.requestPermission(), state == .idle else { return false }
    do {
      try audio.activate()
    } catch {
      return false
    }
    self.assistantID = assistantID
    self.send = send
    self.isOnline = isOnline
    isMuted = false
    listeningFailed = false
    failures = 0
    state = isOnline ? .listening : .connecting
    startListening()
    guard state != .idle else { return false }
    self.onEnd = onEnd
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
    stopListening()
    speaker.stop()
    audio.deactivate()
    replies = []
    spokenIDs = []
    send = nil
    isMuted = false
    listeningFailed = false
    state = .idle
    let onEnd = onEnd
    self.onEnd = nil
    onEnd?()
  }

  func setMuted(_ muted: Bool) {
    guard state != .idle, muted != isMuted else { return }
    isMuted = muted
    if muted {
      stopListening()
    } else {
      startListening()
    }
  }

  /// Queues a new text message of the Assistant to be spoken.
  func receive(_ event: Event) {
    guard state != .idle, event.assistantID == assistantID, event.type == .textMessage,
      event.sender == .assistant, !event.deleted,
      let text = event.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
      spokenIDs.insert(event.id).inserted
    else { return }
    replies.append(text)
    if state != .speaking {
      speakNext()
    }
  }

  private func speakNext() {
    guard !replies.isEmpty else {
      state = isOnline ? .listening : .connecting
      startListening()
      return
    }
    stopListening()
    state = .speaking
    speaker.speak(replies.removeFirst()) { [weak self] in
      guard let self, state == .speaking else { return }
      speakNext()
    }
  }

  private var canHear: Bool { (state == .listening || state == .connecting) && !isMuted && !listeningFailed }

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
    heard = ""
    level = 0
    listener.stop()
  }

  private func handle(_ event: SpeechEvent) {
    guard canHear else { return }
    switch event {
    case .level(let value):
      level = value
    case .partial(let text):
      heard = text
      failures = 0
      restartSilenceTimer()
    case .final(let text):
      heard = text
      failures = 0
      finishUtterance()
    case .stopped:
      finishUtterance()
    case .failed:
      failures += 1
      finishUtterance()
    }
  }

  private func restartSilenceTimer() {
    silence.restart { [weak self] in self?.finishUtterance() }
  }

  private func finishUtterance() {
    let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
    stopListening()
    if !text.isEmpty {
      failures = 0
      send?(text)
      startListening()
    } else if failures >= Self.maxFailures {
      listeningFailed = true
    } else {
      retry.restart { [weak self] in self?.startListening() }
    }
  }
}
