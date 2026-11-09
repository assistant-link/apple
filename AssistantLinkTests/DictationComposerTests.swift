import Testing

@testable import AssistantLink

struct DictationComposerTests {
  @Test func provisionalWordsFollowTheConfirmedOnesAsTheirOwnRun() {
    let text = DictationComposer.transcript(confirmed: "Call David", provisional: "at nine")
    #expect(String(text.characters) == "Call David at nine")
    let runs = text.runs.map { String(text[$0.range].characters) }
    #expect(runs == ["Call David", " at nine"])
  }

  @Test func onlyProvisionalWordsHaveNoLeadingSpace() {
    let text = DictationComposer.transcript(confirmed: "", provisional: "Call")
    #expect(String(text.characters) == "Call")
  }

  @Test func onlyConfirmedWordsAreOneRun() {
    let text = DictationComposer.transcript(confirmed: "Call David", provisional: "")
    #expect(text.runs.count == 1)
  }

  @Test func elapsedTimeIsMinutesAndSeconds() {
    #expect(DictationComposer.elapsed(1) == "0:01")
    #expect(DictationComposer.elapsed(75) == "1:15")
  }
}
