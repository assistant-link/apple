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

  @Test func theEndOfAnOtherUtteranceIsIgnored() async {
    let speaker = LiveSpeechSpeaker()
    var finishes = 0
    speaker.speak(" ") { finishes += 1 }

    speaker.speechSynthesizer(AVSpeechSynthesizer(), didCancel: AVSpeechUtterance(string: "old"))
    await settle()

    #expect(finishes == 0)
    speaker.stop()
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
  var isReady: Bool
  private(set) var prepares = 0
  private(set) var spoken: [String] = []
  private(set) var stops = 0
  private var onEnd: (@MainActor (ReplySpeechResult) -> Void)?

  init(isReady: Bool) {
    self.isReady = isReady
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
