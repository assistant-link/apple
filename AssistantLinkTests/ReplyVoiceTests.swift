import Testing

@testable import AssistantLink

struct ReplyVoiceTests {
  private func voice(
    _ id: String, _ language: String = "en-US", _ quality: ReplyVoice.Quality = .standard,
    novelty: Bool = false
  ) -> ReplyVoice {
    ReplyVoice(id: id, language: language, quality: quality, isNovelty: novelty)
  }

  @Test func premiumBeatsEnhancedBeatsStandard() {
    let standard = voice("a")
    let enhanced = voice("b", "en-US", .enhanced)
    let premium = voice("c", "en-US", .premium)
    #expect(ReplyVoice.best(of: [standard, enhanced, premium], language: "en-US")?.id == "c")
    #expect(ReplyVoice.best(of: [standard, enhanced], language: "en-US")?.id == "b")
    #expect(ReplyVoice.best(of: [standard], language: "en-US")?.id == "a")
  }

  @Test func aMatchingLanguageBeatsABetterVoiceOfAnOther() {
    let voices = [voice("fr", "fr-FR", .premium), voice("en", "en-US")]
    #expect(ReplyVoice.best(of: voices, language: "en-US")?.id == "en")
  }

  @Test func aVoiceOfAnotherRegionMatches() {
    let voices = [voice("gb", "en-GB", .enhanced), voice("fr", "fr-FR", .premium)]
    #expect(ReplyVoice.best(of: voices, language: "en-US")?.id == "gb")
  }

  @Test func theSameRegionBreaksATieInQuality() {
    let voices = [voice("gb", "en-GB", .enhanced), voice("us", "en-US", .enhanced)]
    #expect(ReplyVoice.best(of: voices, language: "en-US")?.id == "us")
  }

  @Test func noveltyVoicesAreSkipped() {
    let voices = [voice("novelty", "en-US", .premium, novelty: true), voice("plain")]
    #expect(ReplyVoice.best(of: voices, language: "en-US")?.id == "plain")
    #expect(ReplyVoice.best(of: [voices[0]], language: "en-US") == nil)
  }

  @Test func noVoiceInTheLanguageIsNil() {
    #expect(ReplyVoice.best(of: [voice("fr", "fr-FR")], language: "en-US") == nil)
  }

  @Test func noVoicesIsNil() {
    #expect(ReplyVoice.best(of: [], language: "en-US") == nil)
  }
}
