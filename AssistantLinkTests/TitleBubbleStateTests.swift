import Testing

@testable import AssistantLink

struct TitleBubbleStateTests {
  @Test func onlineAndOfflineShowTheStatus() {
    #expect(TitleBubble.State.online.statusText == "Online")
    #expect(TitleBubble.State.offline.statusText == "Offline")
  }

  @Test func inCallShowsTheNameOnly() {
    #expect(TitleBubble.State.inCall.statusText == nil)
  }
}
