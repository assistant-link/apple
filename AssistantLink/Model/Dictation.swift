import Foundation
import Observation

/// Dictation into the message field: the words appear as the user speaks, and they either send
/// them as they are or stop and fix them first.
@MainActor
@Observable
final class Dictation {
  enum Phase: Equatable {
    case idle
    /// Waiting for the permissions and the recognizer.
    case preparing
    case recording
    /// Recording stopped; the owner takes the words with `take()`.
    case editing
  }

  private(set) var phase = Phase.idle
  /// Words the recognizer settled on, after any text that was in the field before.
  private(set) var confirmed = ""
  /// Words it may still change.
  private(set) var provisional = ""
  /// Recent microphone levels, 0 to 1, oldest first.
  private(set) var levels: [Float] = []
  private(set) var seconds = 0
  /// Why the last `start` failed; nil when it started.
  private(set) var failure: VoiceCall.StartFailure?

  static let maxLevels = 24

  private let listener: any SpeechListener
  private let audio: any VoiceAudio
  private var clock: Task<Void, Never>?
  /// Counts the starts, so one that was stopped while asking cannot take over a later one.
  private var attempt = 0

  init(listener: any SpeechListener, audio: any VoiceAudio) {
    self.listener = listener
    self.audio = audio
  }

  /// Everything heard so far, as it would read in the field.
  var text: String { Self.join(confirmed, provisional) }

  /// Starts recording after `existing`, the text already in the field.
  func start(after existing: String = "", assistantName: String? = nil) async {
    guard phase == .idle else { return }
    failure = nil
    phase = .preparing
    attempt += 1
    let mine = attempt
    confirmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
    provisional = ""
    levels = []
    seconds = 0
    let allowed = await audio.requestPermission()
    // Stopped or cancelled while asking.
    guard phase == .preparing, attempt == mine else { return }
    guard allowed else {
      fail(.permissionDenied)
      return
    }
    listener.vocabulary = VoiceCall.vocabulary(assistantName: assistantName)
    do {
      try audio.activate()
      try listener.start { [weak self] in self?.handle($0) }
    } catch {
      audio.deactivate()
      fail(.unavailable)
      return
    }
    phase = .recording
    clock = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        self?.seconds += 1
      }
    }
  }

  /// Stops recording and keeps the words, to fix before sending. While still preparing, it
  /// drops the pending start and keeps only the text that was in the field.
  func stop() {
    switch phase {
    case .recording: finishRecording()
    case .preparing: break
    case .idle, .editing: return
    }
    phase = .editing
  }

  /// Stops recording and returns everything heard, to send at once.
  func send() -> String {
    if phase == .recording { finishRecording() }
    return take()
  }

  /// The words of a stopped recording; the dictation is idle again.
  func take() -> String {
    let result = text
    reset()
    return result
  }

  /// Drops the recording and its words, for example when the screen goes away.
  func cancel() {
    // Not recording: the audio session may belong to a voice call by now.
    if phase == .recording { finishRecording() }
    reset()
  }

  private func fail(_ reason: VoiceCall.StartFailure) {
    reset()
    failure = reason
  }

  private func reset() {
    phase = .idle
    confirmed = ""
    provisional = ""
    levels = []
    seconds = 0
  }

  private func finishRecording() {
    clock?.cancel()
    clock = nil
    listener.stop()
    audio.deactivate()
    confirmed = text
    provisional = ""
  }

  private func handle(_ event: SpeechEvent) {
    guard phase == .recording else { return }
    switch event {
    case .level(let value):
      levels = Array((levels + [value]).suffix(Self.maxLevels))
    case .partial(let words):
      // After a pause the recognizer may start a new segment without a final result; its words
      // no longer include the earlier ones.
      if startsNewSegment(words) { confirmed = text }
      provisional = words
    case .final(let words):
      confirmed = Self.join(confirmed, words)
      provisional = ""
    case .stopped:
      // The recognizer gives up after a silence; the user has not stopped yet.
      confirmed = text
      provisional = ""
      do {
        try listener.start { [weak self] in self?.handle($0) }
      } catch {
        stop()
      }
    case .failed:
      stop()
    }
  }

  /// A revision of the partial result keeps its first word, or at least the words after it, which
  /// the recognizer may rewrite ("two friends" to "to friends later"). Otherwise it started over.
  /// A one-word partial only counts as started over when the next one is longer. Punctuation and
  /// case do not count, as a revision often adds them.
  private func startsNewSegment(_ words: String) -> Bool {
    let old = provisional.split(whereSeparator: \.isWhitespace).map(Self.letters)
    let new = words.split(whereSeparator: \.isWhitespace).map(Self.letters)
    guard let oldFirst = old.first, let newFirst = new.first, oldFirst != newFirst else {
      return false
    }
    let oldTail = old.dropFirst()
    let newTail = new.dropFirst()
    if oldTail.isEmpty { return !newTail.isEmpty }
    return !newTail.starts(with: oldTail)
  }

  private static func letters(_ word: Substring) -> String {
    String(word.filter { $0.isLetter || $0.isNumber }).lowercased()
  }

  private static func join(_ first: String, _ second: String) -> String {
    let second = second.trimmingCharacters(in: .whitespacesAndNewlines)
    if first.isEmpty { return second }
    return second.isEmpty ? first : first + " " + second
  }
}
