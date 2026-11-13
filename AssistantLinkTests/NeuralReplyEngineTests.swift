import Foundation
import Testing

@testable import AssistantLink

actor FakeSynthesizer: SentenceSynthesizing {
  private(set) var synthesized: [String] = []
  private var failing: Set<String> = []
  private var held: Set<String> = []
  private var prepareFails: Bool
  private let reports: [ReplyVoiceStatus]
  private var holdsPreparation = false
  private(set) var prepares = 0

  init(prepareFails: Bool = false, reports: [ReplyVoiceStatus] = []) {
    self.prepareFails = prepareFails
    self.reports = reports
  }

  func fail(on sentence: String) { failing.insert(sentence) }
  func hold(_ sentence: String) { held.insert(sentence) }
  func release(_ sentence: String) { held.remove(sentence) }
  func holdPreparation() { holdsPreparation = true }
  func releasePreparation(failing: Bool = false) {
    prepareFails = failing
    holdsPreparation = false
  }

  func prepare(progress: @escaping @Sendable (ReplyVoiceStatus) -> Void) async throws {
    prepares += 1
    for report in reports { progress(report) }
    while holdsPreparation { try await Task.sleep(for: .milliseconds(5)) }
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

  /// Polls instead of sleeping a fixed time, which a busy CI runner can outlast; the expectations
  /// after it still fail when the condition never comes.
  private func waitUntil(_ condition: () async -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(10)
    while await !condition(), ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  private func waitForPreparation(of engine: NeuralReplyEngine) async {
    await waitUntil { engine.status == .ready || engine.status == .failed }
  }

  private func ready(_ synthesizer: FakeSynthesizer, _ player: FakePlayer) async
    -> NeuralReplyEngine
  {
    let engine = NeuralReplyEngine(synthesizer: synthesizer, player: player)
    engine.prepare()
    await waitForPreparation(of: engine)
    return engine
  }

  @Test func theEngineIsReadyOnceThePreparationSucceeds() async {
    let engine = NeuralReplyEngine(synthesizer: FakeSynthesizer(), player: FakePlayer())
    #expect(!engine.isReady)

    engine.prepare()
    await waitForPreparation(of: engine)

    #expect(engine.isReady)
  }

  @Test func aFailedPreparationLeavesTheEngineNotReady() async {
    let engine = NeuralReplyEngine(
      synthesizer: FakeSynthesizer(prepareFails: true), player: FakePlayer())

    engine.prepare()
    await waitForPreparation(of: engine)

    #expect(!engine.isReady)
    #expect(engine.status == .failed)
  }

  @Test func thePreparationReportsItsProgressUntilReady() async {
    let synthesizer = FakeSynthesizer(reports: [
      .downloading(fraction: nil), .downloading(fraction: 0.25), .preparing,
    ])
    await synthesizer.holdPreparation()
    let engine = NeuralReplyEngine(synthesizer: synthesizer, player: FakePlayer())
    #expect(engine.status == .notStarted)

    engine.prepare()
    await settle()
    #expect(engine.status == .preparing)
    #expect(!engine.isReady)

    await synthesizer.releasePreparation()
    await waitForPreparation(of: engine)
    #expect(engine.status == .ready)
  }

  @Test func theDownloadProgressShowsBeforeTheModelIsLoaded() async {
    let synthesizer = FakeSynthesizer(reports: [.downloading(fraction: 0.25)])
    await synthesizer.holdPreparation()
    let engine = NeuralReplyEngine(synthesizer: synthesizer, player: FakePlayer())

    engine.prepare()
    await waitUntil { engine.status == .downloading(fraction: 0.25) }

    #expect(engine.status == .downloading(fraction: 0.25))
    await synthesizer.releasePreparation()
  }

  @Test func preparingAgainWhileOnTheWayStartsNoSecondDownload() async {
    let synthesizer = FakeSynthesizer()
    await synthesizer.holdPreparation()
    let engine = NeuralReplyEngine(synthesizer: synthesizer, player: FakePlayer())

    engine.prepare()
    await settle()
    engine.prepare()
    engine.prepare()
    await synthesizer.releasePreparation()
    await waitForPreparation(of: engine)
    engine.prepare()
    await settle()

    #expect(await synthesizer.prepares == 1)
    #expect(engine.isReady)
  }

  @Test func aFailedPreparationIsTriedAgain() async {
    let synthesizer = FakeSynthesizer(prepareFails: true)
    let engine = NeuralReplyEngine(synthesizer: synthesizer, player: FakePlayer())
    engine.prepare()
    await waitForPreparation(of: engine)
    #expect(engine.status == .failed)

    await synthesizer.releasePreparation()
    engine.prepare()
    await waitForPreparation(of: engine)

    #expect(await synthesizer.prepares == 2)
    #expect(engine.status == .ready)
  }

  @Test func eachSentenceIsPlayedInOrderAndTheEndComesOnce() async {
    let synthesizer = FakeSynthesizer()
    let player = FakePlayer()
    let engine = await ready(synthesizer, player)
    var results: [ReplySpeechResult] = []

    engine.speak("One. Two! Three?") { results.append($0) }
    await waitUntil { player.clips == 3 }
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
    await waitUntil { player.clips == 1 }
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
    await waitUntil { player.clips == 1 }

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
    await waitUntil { !results.isEmpty }

    #expect(results == [.failed])
    #expect(player.clips == 0)
    #expect(!engine.isReady)
    #expect(engine.status == .failed)
  }

  @Test func aSentenceThatFailsAfterSpeechStartedIsSkipped() async {
    let synthesizer = FakeSynthesizer()
    await synthesizer.fail(on: "Two.")
    let player = FakePlayer()
    let engine = await ready(synthesizer, player)
    var results: [ReplySpeechResult] = []

    engine.speak("One. Two. Three.") { results.append($0) }
    await waitUntil { player.clips == 2 }
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

  @Test func theCrashingVersionsAreStillRecorded() {
    func version(_ major: Int, _ minor: Int) -> OperatingSystemVersion {
      OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
    }
    #expect(KokoroSynthesizer.runsSafely(on: version(18, 6)))
    #expect(KokoroSynthesizer.runsSafely(on: version(26, 3)))
    #expect(!KokoroSynthesizer.runsSafely(on: version(26, 4)))
    #expect(!KokoroSynthesizer.runsSafely(on: version(27, 0)))
  }

  @Test func theDownloadFractionCoversTheWholeDownload() {
    #expect(KokoroSynthesizer.downloadFraction(reported: 0) == 0)
    #expect(KokoroSynthesizer.downloadFraction(reported: 0.25) == 0.5)
    #expect(KokoroSynthesizer.downloadFraction(reported: 0.5) == 1)
    #expect(KokoroSynthesizer.downloadFraction(reported: 0.8) == 1)
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
