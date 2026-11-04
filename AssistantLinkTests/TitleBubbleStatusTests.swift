import Testing

@testable import AssistantLink

struct TitleBubbleStatusTests {
  @Test func onlineAndOfflineShowTheStatus() {
    #expect(TitleBubble.Status.online.statusText == "Online")
    #expect(TitleBubble.Status.offline.statusText == "Offline")
  }

  @Test func inCallShowsTheNameOnly() {
    #expect(TitleBubble.Status.inCall.statusText == nil)
  }

  @Test func everyStatusSpeaksItsState() {
    #expect(TitleBubble.Status.online.accessibilityValue == "Online")
    #expect(TitleBubble.Status.offline.accessibilityValue == "Offline")
    #expect(TitleBubble.Status.inCall.accessibilityValue == "In a voice chat")
  }
}
