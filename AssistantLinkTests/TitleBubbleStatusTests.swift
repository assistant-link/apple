import Testing

@testable import AssistantLink

struct TitleBubbleStatusTests {
  @Test func onlineIdleAndOfflineShowTheStatus() {
    #expect(TitleBubble.Status.online.statusText == "Online")
    #expect(TitleBubble.Status.idle.statusText == "Idle")
    #expect(TitleBubble.Status.offline.statusText == "Offline")
  }

  @Test func inCallSaysSoUnderTheName() {
    #expect(TitleBubble.Status.inCall.statusText == "In call")
  }

  @Test func everyStatusSpeaksItsState() {
    #expect(TitleBubble.Status.online.accessibilityValue == "Online")
    #expect(TitleBubble.Status.idle.accessibilityValue == "Idle")
    #expect(TitleBubble.Status.offline.accessibilityValue == "Offline")
    #expect(TitleBubble.Status.inCall.accessibilityValue == "In call")
  }
}
