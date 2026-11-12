import Foundation

@MainActor
final class FakeListener: SpeechListener {
  var vocabulary: [String] = []
  private var handler: (@MainActor (SpeechEvent) -> Void)?
  private var lastPartial = ""
  var isListening: Bool { handler != nil }

  func start(_ handler: @escaping @MainActor (SpeechEvent) -> Void) throws {
    self.handler = handler
    lastPartial = ""
  }

  /// The final result is the last partial one, at once, so the E2E doesn't wait for it.
  func finish() {
    handler?(.final(lastPartial))
  }

  func stop() {
    handler = nil
  }

  /// Feeds what the recognizer would report word by word; the silence timer ends the utterance.
  func hear(_ transcription: String) async {
    var words: [Substring] = []
    for word in transcription.split(separator: " ") {
      words.append(word)
      lastPartial = words.joined(separator: " ")
      handler?(.partial(lastPartial))
      try? await Task.sleep(for: .milliseconds(50))
    }
  }
}

@MainActor
final class FakeSpeaker: SpeechSpeaker {
  private(set) var spoken: [(text: String, at: ContinuousClock.Instant)] = []
  private var task: Task<Void, Never>?

  func speak(_ text: String, onFinish: @escaping @MainActor () -> Void) {
    spoken.append((text, .now))
    task = Task {
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      onFinish()
    }
  }

  func stop() {
    task?.cancel()
  }
}

@MainActor
final class FakeAudio: VoiceAudio {
  func requestPermission() async -> Bool { true }
  func activate() throws {}
  func observeRouteChanges(_ handler: @escaping @MainActor () -> Void) {}
  func deactivate() {}
}
