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

    let steps = [0, 1, 4].map { throttle.receive("\($0)", at: start.addingTimeInterval($0)) }
    let flushed = throttle.flush(at: start.addingTimeInterval(5))
    let afterFlush = throttle.receive("6", at: start.addingTimeInterval(6))

    #expect(steps == [.announce("0"), .wait(4), .none])
    #expect(flushed == "4")
    #expect(afterFlush == .wait(4))
  }

  @Test func announcesTheLatestActivityWhenTheIntervalEnds() {
    var throttle = AnnouncementThrottle()
    let start = Date(timeIntervalSince1970: 1_791_462_615)

    _ = throttle.receive("Searching the code", at: start)
    _ = throttle.receive("Running the tests", at: start.addingTimeInterval(2))
    let flushed = throttle.flush(at: start.addingTimeInterval(5))
    let again = throttle.flush(at: start.addingTimeInterval(60))

    #expect(flushed == "Running the tests")
    #expect(again == nil)
  }

  @Test func announcesAtOnceAfterAQuietInterval() {
    var throttle = AnnouncementThrottle()
    let start = Date(timeIntervalSince1970: 1_791_462_615)

    _ = throttle.receive("Searching the code", at: start)
    let step = throttle.receive("Running the tests", at: start.addingTimeInterval(5))

    #expect(step == .announce("Running the tests"))
  }

  @Test func aCancelledAnnouncementIsNotMade() {
    var throttle = AnnouncementThrottle()
    let start = Date(timeIntervalSince1970: 1_791_462_615)

    _ = throttle.receive("Searching the code", at: start)
    _ = throttle.receive("Running the tests", at: start.addingTimeInterval(2))
    throttle.cancel()
    let flushed = throttle.flush(at: start.addingTimeInterval(5))

    #expect(flushed == nil)
  }
}
