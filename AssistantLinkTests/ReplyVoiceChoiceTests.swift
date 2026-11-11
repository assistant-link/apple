import Foundation
import Testing

@testable import AssistantLink

@MainActor
struct ReplyVoiceChoiceTests {
  private func emptyDefaults() -> UserDefaults {
    UserDefaults(suiteName: "ReplyVoiceChoiceTests.\(UUID().uuidString)")!
  }

  /// Hands out the engines in order, as the speaker asks for Kokoro.
  private final class Factory {
    let engines: [FakeReplyEngine]
    private(set) var made = 0

    init(_ engines: FakeReplyEngine...) { self.engines = engines }

    @MainActor func make() -> any ReplySpeechEngine {
      defer { made += 1 }
      return engines[min(made, engines.count - 1)]
    }
  }

  private func speaker(
    _ defaults: UserDefaults, english: Bool = true, factory: Factory
  ) -> LiveSpeechSpeaker {
    LiveSpeechSpeaker(defaults: defaults, isEnglish: english, kokoro: { factory.make() })
  }

  @Test func theChoiceDefaultsToTheAppleVoice() {
    #expect(ReplyVoiceChoice.current(defaults: emptyDefaults()) == .apple)
  }

  @Test func registeringDefaultsSelectsTheAppleVoice() {
    let defaults = emptyDefaults()
    ReplyVoiceChoice.registerDefaults(in: defaults)
    #expect(defaults.string(forKey: ReplyVoiceChoice.key) == "apple")
  }

  @Test func anUnknownValueMeansTheAppleVoice() {
    let defaults = emptyDefaults()
    defaults.set("other", forKey: ReplyVoiceChoice.key)
    #expect(ReplyVoiceChoice.current(defaults: defaults) == .apple)
  }

  @Test func kokoroIsUsedWhenChosen() {
    let defaults = emptyDefaults()
    defaults.set("kokoro", forKey: ReplyVoiceChoice.key)
    let engine = FakeReplyEngine(isReady: true)
    let speaker = speaker(defaults, factory: Factory(engine))

    speaker.prepareForCall()
    speaker.speak("Hello.") {}

    #expect(engine.spoken == ["Hello."])
  }

  @Test func theAppleVoiceNeverCreatesKokoro() {
    let factory = Factory(FakeReplyEngine(isReady: true))
    let speaker = speaker(emptyDefaults(), factory: factory)

    speaker.prepareForCall()
    speaker.speak(" ") {}

    #expect(factory.made == 0)
    #expect(speaker.current != nil)
    speaker.stop()
  }

  @Test func kokoroIsNotUsedForOtherLanguages() {
    let defaults = emptyDefaults()
    defaults.set("kokoro", forKey: ReplyVoiceChoice.key)
    let factory = Factory(FakeReplyEngine(isReady: true))
    let speaker = speaker(defaults, english: false, factory: factory)

    speaker.prepareForCall()

    #expect(factory.made == 0)
  }

  @Test func aChangeIsHonouredAtTheNextCall() {
    let defaults = emptyDefaults()
    let engine = FakeReplyEngine(isReady: true)
    let speaker = speaker(defaults, factory: Factory(engine))
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
    let factory = Factory(FakeReplyEngine(isReady: true), FakeReplyEngine(isReady: true))
    let speaker = speaker(defaults, factory: factory)

    speaker.prepareForCall()
    speaker.prepareForCall()

    #expect(factory.made == 1)
  }

  @Test func kokoroNotYetReadySpeaksWithTheSystemVoiceAndPrepares() {
    let defaults = emptyDefaults()
    defaults.set("kokoro", forKey: ReplyVoiceChoice.key)
    let engine = FakeReplyEngine(isReady: false)
    let speaker = speaker(defaults, factory: Factory(engine))

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
    let speaker = speaker(defaults, factory: Factory(engine))
    speaker.prepareForCall()
    speaker.speak(" ") {}

    engine.end(.failed)

    #expect(speaker.current != nil)
    speaker.stop()
  }

  @Test func kokoroIsNotBlockedOnVersionsWhereCoreMLCrashes() {
    // The opt-in bypasses `runsSafely`, which stays as the record of the crash.
    let defaults = emptyDefaults()
    defaults.set("kokoro", forKey: ReplyVoiceChoice.key)
    let engine = FakeReplyEngine(isReady: true)
    let speaker = speaker(defaults, factory: Factory(engine))
    let ios27 = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)
    #expect(!KokoroSynthesizer.runsSafely(on: ios27))

    speaker.prepareForCall()
    speaker.speak("Hello.") {}

    #expect(engine.spoken == ["Hello."])
  }
}
