import Testing

@testable import AssistantLink

actor FakeSynthesizer: SentenceSynthesizing {
  private(set) var synthesized: [String] = []
  private var failing: Set<String> = []
  private var held: Set<String> = []
  private var prepareFails: Bool

  init(prepareFails: Bool = false) {
    self.prepareFails = prepareFails
  }

  func fail(on sentence: String) { failing.insert(sentence) }
  func hold(_ sentence: String) { held.insert(sentence) }
  func release(_ sentence: String) { held.remove(sentence) }

  func prepare() async throws {
    if prepareFails { throw FakeFailure() }
  }

  func synthesize(_ sentence: String) async throws -> SpeechClip {
    while held.contains(sentence) { try await Task.sleep(for: .milliseconds(5)) }
    if failing.contains(sentence) { throw FakeFailure() }
    synthesized.append(sentence)
    return SpeechClip(samples: [0], sampleRate: 24_000)
  }
}

struct FakeFailure: Error {}

@MainActor
final class FakePlayer: SamplePlaying {
  private(set) var clips = 0
  private(set) var stops = 0
  private var drained: (@MainActor () -> Void)?

  func enqueue(_ clip: SpeechClip) throws { clips += 1 }
  func whenDrained(_ handler: @escaping @MainActor () -> Void) { drained = handler }
  func stop() {
    stops += 1
    drained = nil
  }

  func finishPlaying() {
    let handler = drained
    drained = nil
    handler?()
  }
}

@MainActor
struct NeuralReplyEngineTests {
  private func settle() async {
    try? await Task.sleep(for: .milliseconds(100))
  }

  private func ready(_ synthesizer: FakeSynthesizer, _ player: FakePlayer) async
    -> NeuralReplyEngine
  {
    let engine = NeuralReplyEngine(synthesizer: synthesizer, player: player)
    engine.prepare()
    await settle()
    return engine
  }

  @Test func theEngineIsReadyOnceThePreparationSucceeds() async {
    let engine = NeuralReplyEngine(synthesizer: FakeSynthesizer(), player: FakePlayer())
    #expect(!engine.isReady)

    engine.prepare()
    await settle()

    #expect(engine.isReady)
  }

  @Test func aFailedPreparationLeavesTheEngineNotReady() async {
    let engine = NeuralReplyEngine(
      synthesizer: FakeSynthesizer(prepareFails: true), player: FakePlayer())

    engine.prepare()
    await settle()

    #expect(!engine.isReady)
  }

  @Test func eachSentenceIsPlayedInOrderAndTheEndComesOnce() async {
    let synthesizer = FakeSynthesizer()
    let player = FakePlayer()
    let engine = await ready(synthesizer, player)
    var results: [ReplySpeechResult] = []

    engine.speak("One. Two! Three?") { results.append($0) }
    await settle()
    #expect(await synthesizer.synthesized == ["One.", "Two!", "Three?"])
    #expect(player.clips == 3)
    #expect(results.isEmpty)

    player.finishPlaying()
    player.finishPlaying()
    #expect(results == [.finished])
  }

  @Test func theFirstSentenceIsPlayedBeforeTheNextIsSynthesized() async {
    let synthesizer = FakeSynthesizer()
    await synthesizer.hold("Two.")
    let player = FakePlayer()
    let engine = await ready(synthesizer, player)

    engine.speak("One. Two.") { _ in }
    await settle()

    #expect(player.clips == 1)
    engine.stop()
  }

  @Test func stoppingCancelsTheQueuedSentences() async {
    let synthesizer = FakeSynthesizer()
    await synthesizer.hold("Two.")
    let player = FakePlayer()
    let engine = await ready(synthesizer, player)
    var results: [ReplySpeechResult] = []
    engine.speak("One. Two. Three.") { results.append($0) }
    await settle()

    engine.stop()
    await synthesizer.release("Two.")
    await settle()
    player.finishPlaying()

    #expect(player.clips == 1)
    #expect(player.stops >= 1)
    #expect(await synthesizer.synthesized == ["One."])
    #expect(results.isEmpty)
  }

  @Test func aFailureBeforeAnythingPlayedIsReportedAndMarksTheEngineNotReady() async {
    let synthesizer = FakeSynthesizer()
    await synthesizer.fail(on: "One.")
    let player = FakePlayer()
    let engine = await ready(synthesizer, player)
    var results: [ReplySpeechResult] = []

    engine.speak("One. Two.") { results.append($0) }
    await settle()

    #expect(results == [.failed])
    #expect(player.clips == 0)
    #expect(!engine.isReady)
  }

  @Test func aSentenceThatFailsAfterSpeechStartedIsSkipped() async {
    let synthesizer = FakeSynthesizer()
    await synthesizer.fail(on: "Two.")
    let player = FakePlayer()
    let engine = await ready(synthesizer, player)
    var results: [ReplySpeechResult] = []

    engine.speak("One. Two. Three.") { results.append($0) }
    await settle()
    player.finishPlaying()

    #expect(player.clips == 2)
    #expect(results == [.finished])
  }

  @Test func blankTextEndsAtOnce() async {
    let engine = await ready(FakeSynthesizer(), FakePlayer())
    var results: [ReplySpeechResult] = []

    engine.speak("  \n ") { results.append($0) }

    #expect(results == [.finished])
  }

  @Test func theNeuralVoiceIsNotUsedWhereTheModelCrashes() {
    func version(_ major: Int, _ minor: Int) -> OperatingSystemVersion {
      OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
    }
    #expect(KokoroSynthesizer.runsSafely(on: version(18, 6)))
    #expect(KokoroSynthesizer.runsSafely(on: version(26, 3)))
    #expect(!KokoroSynthesizer.runsSafely(on: version(26, 4)))
    #expect(!KokoroSynthesizer.runsSafely(on: version(27, 0)))
  }
}

struct SentenceSplitterTests {
  @Test func textSplitsAtSentenceEnds() {
    #expect(
      SentenceSplitter.sentences(in: "Hello there. How are you? Fine!")
        == ["Hello there.", "How are you?", "Fine!"])
  }

  @Test func textWithoutPunctuationIsOneSentence() {
    #expect(SentenceSplitter.sentences(in: "no punctuation here") == ["no punctuation here"])
  }

  @Test func lineBreaksSeparateSentences() {
    #expect(
      SentenceSplitter.sentences(in: "First line\nSecond line") == ["First line", "Second line"])
  }

  @Test func blankTextHasNoSentences() {
    #expect(SentenceSplitter.sentences(in: " \n ").isEmpty)
  }
}
