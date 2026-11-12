import Foundation
import Testing

@testable import AssistantLink

@MainActor
struct ReplyVoiceChoiceTests {
  private func emptyDefaults(suite: String = "ReplyVoiceChoiceTests.\(UUID().uuidString)")
    -> UserDefaults
  {
    UserDefaults(suiteName: suite)!
  }

  private func appleDefaults() -> UserDefaults {
    let defaults = emptyDefaults()
    defaults.set("apple", forKey: ReplyVoiceChoice.key)
    return defaults
  }

  private func speaker(
    _ defaults: UserDefaults, english: Bool = true, safe: Bool = true,
    factory: FakeKokoroFactory
  ) -> LiveSpeechSpeaker {
    LiveSpeechSpeaker(
      kokoro: KokoroVoice(
        defaults: defaults, isEnglish: english, runsSafely: safe, make: { factory.make() }))
  }

  @Test func theChoiceDefaultsToKokoro() {
    #expect(ReplyVoiceChoice.current(defaults: emptyDefaults()) == .kokoro)
  }

  @Test func registeringDefaultsSelectsKokoroWithoutWritingTheKey() {
    let suite = "ReplyVoiceChoiceTests.\(UUID().uuidString)"
    let defaults = emptyDefaults(suite: suite)
    ReplyVoiceChoice.registerDefaults(in: defaults)
    #expect(defaults.string(forKey: ReplyVoiceChoice.key) == "kokoro")
    #expect(defaults.persistentDomain(forName: suite)?[ReplyVoiceChoice.key] == nil)
  }

  @Test func anExplicitAppleChoiceIsKept() {
    let defaults = appleDefaults()
    ReplyVoiceChoice.registerDefaults(in: defaults)
    #expect(ReplyVoiceChoice.current(defaults: defaults) == .apple)
  }

  @Test func anExplicitKokoroChoiceIsKept() {
    let defaults = emptyDefaults()
    defaults.set("kokoro", forKey: ReplyVoiceChoice.key)
    ReplyVoiceChoice.registerDefaults(in: defaults)
    #expect(ReplyVoiceChoice.current(defaults: defaults) == .kokoro)
  }

  @Test func anUnknownValueMeansTheDefault() {
    let defaults = emptyDefaults()
    defaults.set("other", forKey: ReplyVoiceChoice.key)
    #expect(ReplyVoiceChoice.current(defaults: defaults) == .kokoro)
  }

  @Test func aValueOfAnotherTypeMeansTheDefault() {
    let defaults = emptyDefaults()
    defaults.set(3, forKey: ReplyVoiceChoice.key)
    #expect(ReplyVoiceChoice.current(defaults: defaults) == .kokoro)
  }

  @Test func kokoroIsUsedWhenChosen() {
    let defaults = emptyDefaults()
    defaults.set("kokoro", forKey: ReplyVoiceChoice.key)
    let engine = FakeReplyEngine(isReady: true)
    let speaker = speaker(defaults, factory: FakeKokoroFactory(engine))

    speaker.prepareForCall()
    speaker.speak("Hello.") {}

    #expect(engine.spoken == ["Hello."])
  }

  @Test func theAppleVoiceNeverCreatesKokoro() {
    let factory = FakeKokoroFactory(FakeReplyEngine(isReady: true))
    let speaker = speaker(appleDefaults(), factory: factory)

    speaker.prepareForCall()
    speaker.speak(" ") {}

    #expect(factory.made == 0)
    #expect(speaker.current != nil)
    speaker.stop()
  }

  @Test func kokoroIsNotUsedForOtherLanguages() {
    let defaults = emptyDefaults()
    defaults.set("kokoro", forKey: ReplyVoiceChoice.key)
    let factory = FakeKokoroFactory(FakeReplyEngine(isReady: true))
    let speaker = speaker(defaults, english: false, factory: factory)

    speaker.prepareForCall()

    #expect(factory.made == 0)
  }

  @Test func aChangeIsHonouredAtTheNextCall() {
    let defaults = appleDefaults()
    let engine = FakeReplyEngine(isReady: true)
    let speaker = speaker(defaults, factory: FakeKokoroFactory(engine))
    speaker.prepareForCall()
    speaker.speak(" ") {}
    #expect(engine.spoken.isEmpty)
    speaker.stop()

    defaults.set("kokoro", forKey: ReplyVoiceChoice.key)
    speaker.prepareForCall()
    speaker.speak("Hi.") {}
    #expect(engine.spoken == ["Hi."])
    speaker.stop()

    defaults.set("apple", forKey: ReplyVoiceChoice.key)
    speaker.prepareForCall()
    speaker.speak(" ") {}
    #expect(engine.spoken == ["Hi."])
    speaker.stop()
  }

  @Test func kokoroIsCreatedOnceAcrossCalls() {
    let defaults = emptyDefaults()
    defaults.set("kokoro", forKey: ReplyVoiceChoice.key)
    let factory = FakeKokoroFactory(
      FakeReplyEngine(isReady: true), FakeReplyEngine(isReady: true))
    let speaker = speaker(defaults, factory: factory)

    speaker.prepareForCall()
    speaker.prepareForCall()

    #expect(factory.made == 1)
  }

  @Test func kokoroNotYetReadySpeaksWithTheSystemVoiceAndPrepares() {
    let defaults = emptyDefaults()
    defaults.set("kokoro", forKey: ReplyVoiceChoice.key)
    let engine = FakeReplyEngine(isReady: false)
    let speaker = speaker(defaults, factory: FakeKokoroFactory(engine))

    speaker.prepareForCall()
    speaker.speak(" ") {}

    #expect(engine.prepares >= 1)
    #expect(engine.spoken.isEmpty)
    #expect(speaker.current != nil)
    speaker.stop()
  }

  @Test func aFailingKokoroFallsBackToTheSystemVoice() {
    let defaults = emptyDefaults()
    defaults.set("kokoro", forKey: ReplyVoiceChoice.key)
    let engine = FakeReplyEngine(isReady: true)
    let speaker = speaker(defaults, factory: FakeKokoroFactory(engine))
    speaker.prepareForCall()
    speaker.speak(" ") {}

    engine.end(.failed)

    #expect(speaker.current != nil)
    speaker.stop()
  }

  @Test func kokoroSpeaksInCallsOnVersionsWhereCoreMLCrashes() {
    let engine = FakeReplyEngine(isReady: true)
    let factory = FakeKokoroFactory(engine)
    let speaker = speaker(emptyDefaults(), safe: false, factory: factory)

    speaker.prepareForCall()
    speaker.speak("Hello.") {}

    #expect(factory.made == 1)
    #expect(engine.prepares >= 1)
    #expect(engine.spoken == ["Hello."])
  }

  @Test func theAppleVoiceSpeaksWhenChosenOnVersionsWhereCoreMLCrashes() {
    let factory = FakeKokoroFactory(FakeReplyEngine(isReady: true))
    let speaker = speaker(appleDefaults(), safe: false, factory: factory)

    speaker.prepareForCall()
    speaker.speak(" ") {}

    #expect(factory.made == 0)
    #expect(speaker.current != nil)
    speaker.stop()
  }
}
