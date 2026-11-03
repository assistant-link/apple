import Foundation

@MainActor
final class FakeListener: SpeechListener {
  private var handler: (@MainActor (SpeechEvent) -> Void)?
  var isListening: Bool { handler != nil }

  func start(_ handler: @escaping @MainActor (SpeechEvent) -> Void) throws {
    self.handler = handler
  }

  func stop() {
    handler = nil
  }

  /// Feeds what the recognizer would report word by word; the silence timer ends the utterance.
  func hear(_ transcription: String) async {
    var words: [Substring] = []
    for word in transcription.split(separator: " ") {
      words.append(word)
      handler?(.partial(words.joined(separator: " ")))
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
  func deactivate() {}
}
