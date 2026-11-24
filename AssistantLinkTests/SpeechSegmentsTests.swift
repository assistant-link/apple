import Testing

@testable import AssistantLink

struct SpeechSegmentsTests {
  @Test func wordsAddedBeforeTheEarlierOnesAreARevision() {
    #expect(!SpeechSegments.startsNew("I think the cool one is", after: "the cool one"))
  }

  @Test func differentWordsStartANewSegment() {
    #expect(SpeechSegments.startsNew("so you can change it", after: "the cool one"))
  }

  @Test func aFinalResultThatRepeatsTheEarlierSegmentsReplacesThem() {
    #expect(
      SpeechSegments.final("Remind me to call David.", after: "remind me")
        == "Remind me to call David.")
  }

  @Test func aFinalResultOfTheLastSegmentFollowsTheEarlierOnes() {
    #expect(
      SpeechSegments.final("to call David.", after: "remind me") == "remind me to call David.")
  }

  @Test func aFinalResultWithoutEarlierSegmentsIsKeptAsItIs() {
    #expect(SpeechSegments.final(" Hello there ", after: "") == "Hello there")
  }
}
