import Foundation
import Testing

@testable import AssistantLink

@MainActor
struct KokoroVoiceTests {
  private func defaults(_ choice: String? = nil) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "KokoroVoiceTests.\(UUID().uuidString)")!
    ReplyVoiceChoice.registerDefaults(in: defaults)
    if let choice { defaults.set(choice, forKey: ReplyVoiceChoice.key) }
    return defaults
  }

  private func voice(
    _ defaults: UserDefaults, english: Bool = true, safe: Bool = true,
    factory: FakeKokoroFactory
  ) -> KokoroVoice {
    KokoroVoice(defaults: defaults, isEnglish: english, runsSafely: safe, make: { factory.make() })
  }

  @Test func preparingStartsKokoroByDefault() {
    let engine = FakeReplyEngine(isReady: false)
    let factory = FakeKokoroFactory(engine)

    voice(defaults(), factory: factory).prepare()

    #expect(factory.made == 1)
    #expect(engine.prepares == 1)
  }

  @Test func preparingDoesNothingWhenTheAppleVoiceIsChosen() {
    let factory = FakeKokoroFactory(FakeReplyEngine(isReady: false))

    voice(defaults("apple"), factory: factory).prepare()

    #expect(factory.made == 0)
  }

  @Test func preparingDoesNothingOnVersionsWhereCoreMLCrashes() {
    let factory = FakeKokoroFactory(FakeReplyEngine(isReady: false))

    voice(defaults(), safe: false, factory: factory).prepare()

    #expect(factory.made == 0)
  }

  @Test func preparingLeavesTheEngineOfACallAloneOnVersionsWhereCoreMLCrashes() {
    let engine = FakeReplyEngine(isReady: false)
    let voice = voice(defaults(), safe: false, factory: FakeKokoroFactory(engine))
    _ = voice.usedEngine()

    voice.prepare()

    #expect(engine.prepares == 0)
  }

  @Test func callsUseKokoroOnVersionsWhereCoreMLCrashes() {
    let engine = FakeReplyEngine(isReady: false)
    let factory = FakeKokoroFactory(engine)
    let voice = voice(defaults(), safe: false, factory: factory)

    #expect(voice.usedEngine() === engine)
    #expect(voice.usedEngine() === engine)
    #expect(factory.made == 1)
    #expect(engine.prepares == 0)
  }

  @Test func callsUseTheAppleVoiceWhenChosenOnVersionsWhereCoreMLCrashes() {
    let factory = FakeKokoroFactory(FakeReplyEngine(isReady: false))
    let voice = voice(defaults("apple"), safe: false, factory: factory)

    #expect(voice.usedEngine() == nil)
    voice.retry()
    #expect(factory.made == 0)
  }

  @Test func retryingPreparesKokoroOnVersionsWhereCoreMLCrashes() {
    let engine = FakeReplyEngine(isReady: false)
    let factory = FakeKokoroFactory(engine)

    voice(defaults(), safe: false, factory: factory).retry()

    #expect(factory.made == 1)
    #expect(engine.prepares == 1)
  }

  @Test func preparingDoesNothingForOtherLanguages() {
    let factory = FakeKokoroFactory(FakeReplyEngine(isReady: false))

    voice(defaults("kokoro"), english: false, factory: factory).prepare()

    #expect(factory.made == 0)
  }

  @Test func theSystemSaysWhetherCoreMLIsSafe() {
    let safe = KokoroSynthesizer.runsSafely(on: ProcessInfo.processInfo.operatingSystemVersion)
    let factory = FakeKokoroFactory(FakeReplyEngine(isReady: false))
    let voice = KokoroVoice(defaults: defaults("kokoro"), isEnglish: true, make: { factory.make() })

    voice.prepare()

    #expect(factory.made == (safe ? 1 : 0))
  }

  @Test func theSpeakerUsesTheEngineThatWasPreparedAtLaunch() {
    let engine = FakeReplyEngine(isReady: false)
    let factory = FakeKokoroFactory(engine, FakeReplyEngine(isReady: true))
    let voice = voice(defaults(), factory: factory)
    let speaker = LiveSpeechSpeaker(kokoro: voice)
    voice.prepare()
    voice.prepare()

    speaker.prepareForCall()
    speaker.speak(" ") {}

    #expect(factory.made == 1)
    #expect(engine.spoken.isEmpty)
    #expect(speaker.current != nil)
    speaker.stop()

    engine.status = .ready
    speaker.speak("Hello.") {}

    #expect(engine.spoken == ["Hello."])
  }

  @Test func theStatusIsNotStartedUntilKokoroIsMade() {
    let factory = FakeKokoroFactory(FakeReplyEngine(isReady: false))

    #expect(voice(defaults(), factory: factory).status == .notStarted)
    #expect(factory.made == 0)
  }

  @Test func theStatusFollowsTheEngine() {
    let engine = FakeReplyEngine(isReady: false)
    let voice = voice(defaults(), factory: FakeKokoroFactory(engine))
    voice.prepare()

    engine.status = .downloading(fraction: 0.4)
    #expect(voice.status == .downloading(fraction: 0.4))

    engine.status = .failed
    #expect(voice.status == .failed)

    engine.status = .ready
    #expect(voice.status == .ready)
  }

  @Test func thereIsNoStatusWhenKokoroIsNotUsed() {
    let engine = FakeReplyEngine(isReady: false)
    let defaults = defaults()
    let voice = voice(defaults, factory: FakeKokoroFactory(engine))
    voice.prepare()

    defaults.set("apple", forKey: ReplyVoiceChoice.key)

    #expect(voice.status == nil)
    let other = self.voice(
      self.defaults(), english: false, factory: FakeKokoroFactory(FakeReplyEngine(isReady: true)))
    #expect(other.status == nil)
  }

  @Test func theStatusFollowsTheEngineOfACallOnVersionsWhereCoreMLCrashes() {
    let engine = FakeReplyEngine(isReady: false)
    let voice = voice(defaults(), safe: false, factory: FakeKokoroFactory(engine))
    #expect(voice.status == .notStarted)

    _ = voice.usedEngine()
    engine.status = .downloading(fraction: 0.2)

    #expect(voice.status == .downloading(fraction: 0.2))
  }

  @Test func theModelDownloadsOnCellular() {
    #expect(KokoroSynthesizer.downloadsOnAnyNetwork)
  }
}
