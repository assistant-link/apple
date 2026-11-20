import Foundation
import Testing

@testable import AssistantLink

struct AgentActivityTests {
  @Test func showsTheTextAsSent() {
    #expect(AgentActivity.text("Searching the code…") == "Searching the code…")
  }

  @Test func noTextOrBlankTextIsNoActivity() {
    #expect(AgentActivity.text(nil) == nil)
    #expect(AgentActivity.text("") == nil)
    #expect(AgentActivity.text(" \n\t ") == nil)
  }

  @Test func makesTheTextOneLine() {
    #expect(AgentActivity.text("  Reading\n\nthe\tlogs…\u{7} ") == "Reading the logs…")
  }

  @Test func cutsTextOverSixtyCharactersAndEndsItInAnEllipsis() {
    let a = { (count: Int) in String(repeating: "a", count: count) }

    #expect(AgentActivity.text(a(60)) == a(60))
    #expect(AgentActivity.text(a(61)) == a(59) + "…")
    #expect(AgentActivity.text(a(58) + " bc") == a(58) + "…")
  }

  @Test func readsTheNameAndTheTextWithoutItsEllipsis() {
    #expect(
      AgentActivity.accessibilityLabel("Searching the code…", name: "Hermes")
        == "Hermes: Searching the code")
    #expect(AgentActivity.accessibilityLabel("Testing...", name: "Hermes") == "Hermes: Testing")
  }

  @Test func noActivityReadsAsWorking() {
    #expect(AgentActivity.accessibilityLabel(nil, name: "Hermes") == "Working")
  }

  @Test func announcesAtMostOnceEveryFewSeconds() {
    var throttle = AnnouncementThrottle()
    let start = Date(timeIntervalSince1970: 1_791_462_615)

    let allowed = [0, 1, 4, 5].map { throttle.allows(at: start.addingTimeInterval($0)) }

    #expect(allowed == [true, false, false, true])
  }
}
