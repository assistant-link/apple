import AVFoundation
import Testing

@testable import AssistantLink

@MainActor
struct LiveSpeechSpeakerTests {
  private func settle() async {
    try? await Task.sleep(for: .milliseconds(50))
  }

  @Test func aCancelledUtteranceFinishesTheSpeech() async throws {
    let speaker = LiveSpeechSpeaker()
    var finishes = 0
    speaker.speak(" ") { finishes += 1 }
    let utterance = try #require(speaker.current)

    speaker.speechSynthesizer(AVSpeechSynthesizer(), didCancel: utterance)
    await settle()

    #expect(finishes == 1)
  }

  @Test func theEndOfAnOtherUtteranceIsIgnored() async throws {
    let speaker = LiveSpeechSpeaker()
    var finishes = 0
    speaker.speak(" ") { finishes += 1 }
    let utterance = try #require(speaker.current)
    let synthesizer = try #require(
      Mirror(reflecting: speaker).children.lazy.compactMap { $0.value as? AVSpeechSynthesizer }
        .first)
    // Keeps the real synthesizer, which may finish " " within the settle, from finishing the speech.
    synthesizer.delegate = nil

    speaker.speechSynthesizer(synthesizer, didCancel: AVSpeechUtterance(string: "old"))
    speaker.speechSynthesizer(synthesizer, didFinish: AVSpeechUtterance(string: "older"))
    await settle()

    #expect(finishes == 0)
    #expect(speaker.current === utterance)
    speaker.speechSynthesizer(synthesizer, didCancel: utterance)
    await settle()
    #expect(finishes == 1)
  }

  @Test func stoppingDoesNotFinishTheSpeech() async throws {
    let speaker = LiveSpeechSpeaker()
    var finishes = 0
    speaker.speak(" ") { finishes += 1 }
    let utterance = try #require(speaker.current)

    speaker.stop()
    speaker.speechSynthesizer(AVSpeechSynthesizer(), didCancel: utterance)
    await settle()

    #expect(finishes == 0)
  }
}

@MainActor
final class FakeReplyEngine: ReplySpeechEngine {
  var status: ReplyVoiceStatus
  private(set) var prepares = 0
  private(set) var spoken: [String] = []
  private(set) var stops = 0
  private var onEnd: (@MainActor (ReplySpeechResult) -> Void)?

  init(isReady: Bool) {
    status = isReady ? .ready : .notStarted
  }

  func prepare() { prepares += 1 }

  func speak(_ text: String, onEnd: @escaping @MainActor (ReplySpeechResult) -> Void) {
    spoken.append(text)
    self.onEnd = onEnd
  }

  func stop() {
    stops += 1
    onEnd = nil
  }

  func end(_ result: ReplySpeechResult) { onEnd?(result) }
}

/// Hands out the engines in order, as Kokoro is asked for.
@MainActor
final class FakeKokoroFactory {
  let engines: [FakeReplyEngine]
  private(set) var made = 0

  init(_ engines: FakeReplyEngine...) { self.engines = engines }

  func make() -> any ReplySpeechEngine {
    defer { made += 1 }
    return engines[min(made, engines.count - 1)]
  }
}

@MainActor
struct ReplyEngineSelectionTests {
  private func settle() async {
    try? await Task.sleep(for: .milliseconds(50))
  }

  @Test func anEngineNotReadyLeavesTheSpeechToTheSystemVoice() {
    let engine = FakeReplyEngine(isReady: false)
    let speaker = LiveSpeechSpeaker(engine: engine)

    speaker.speak(" ") {}

    #expect(engine.spoken.isEmpty)
    #expect(speaker.current != nil)
    #expect(engine.prepares >= 1)
    speaker.stop()
  }

  @Test func aReadyEngineSpeaksInsteadOfTheSystemVoice() {
    let engine = FakeReplyEngine(isReady: true)
    let speaker = LiveSpeechSpeaker(engine: engine)

    speaker.speak("Hello.") {}

    #expect(engine.spoken == ["Hello."])
    #expect(speaker.current == nil)
  }

  @Test func theEndOfTheEngineFinishesTheSpeechOnce() {
    let engine = FakeReplyEngine(isReady: true)
    let speaker = LiveSpeechSpeaker(engine: engine)
    var finishes = 0
    speaker.speak("Hello.") { finishes += 1 }

    engine.end(.finished)
    engine.end(.finished)

    #expect(finishes == 1)
  }

  @Test func stoppingCancelsTheEngineWithoutFinishing() {
    let engine = FakeReplyEngine(isReady: true)
    let speaker = LiveSpeechSpeaker(engine: engine)
    var finishes = 0
    speaker.speak("Hello.") { finishes += 1 }

    speaker.stop()
    engine.end(.finished)

    #expect(engine.stops >= 1)
    #expect(finishes == 0)
  }

  @Test func aFailedEngineFallsBackToTheSystemVoice() {
    let engine = FakeReplyEngine(isReady: true)
    let speaker = LiveSpeechSpeaker(engine: engine)
    var finishes = 0
    speaker.speak(" ") { finishes += 1 }

    engine.end(.failed)

    #expect(speaker.current != nil)
    #expect(finishes == 0)
    speaker.stop()
  }
}
