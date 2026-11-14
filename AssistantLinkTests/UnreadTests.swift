import Foundation
import Testing

@testable import AssistantLink

struct UnreadTests {
  private let assistantID = "as-1"

  private func marks() -> ReadMarks {
    ReadMarks(defaults: UserDefaults(suiteName: "UnreadTests.\(UUID().uuidString)")!)
  }

  private func incoming(_ id: String) -> Event {
    .stub(id, assistantID: assistantID)
  }

  private func own(_ id: String, via: Event.Via? = nil) -> Event {
    Event(
      id: id, assistantID: assistantID, type: .textMessage, sender: .user,
      createdAt: Date(timeIntervalSince1970: 0), text: id, via: via)
  }

  /// Opens the conversation and places the divider once its events have loaded.
  private func visit(_ events: [Event], marks: ReadMarks) -> ConversationVisit {
    var visit = ConversationVisit()
    visit.open()
    visit.place(in: events, lastReadID: marks.lastReadID(assistantID: assistantID))
    return visit
  }

  @Test func noDividerWhenNothingIsUnread() {
    let marks = marks()
    let events = [own("e1"), incoming("e2")]
    marks.markRead(events, assistantID: assistantID)

    #expect(visit(events, marks: marks).dividerRowID == nil)
  }

  @Test func noDividerInAConversationNeverReadOnThisDevice() {
    #expect(visit([incoming("e1")], marks: marks()).dividerRowID == nil)
  }

  @Test func theDividerSitsAtTheFirstUnreadIncomingMessage() {
    let marks = marks()
    marks.markRead([incoming("e1")], assistantID: assistantID)

    let visit = visit([incoming("e1"), incoming("e2"), incoming("e3")], marks: marks)

    #expect(visit.dividerRowID == "e2")
  }

  @Test func ownMessagesNeverCountAsUnread() {
    let marks = marks()
    marks.markRead([incoming("e1")], assistantID: assistantID)

    #expect(
      visit([incoming("e1"), own("e2"), own("e3", via: .voice)], marks: marks).dividerRowID == nil)
    #expect(
      visit([incoming("e1"), own("e2"), incoming("e3")], marks: marks).dividerRowID == "e3")
  }

  @Test func callEventsAreNotUnreadMessages() {
    let marks = marks()
    marks.markRead([incoming("e1")], assistantID: assistantID)
    let call = Event(
      id: "e2", assistantID: assistantID, type: .callEnded, sender: .system,
      createdAt: Date(timeIntervalSince1970: 0))

    #expect(visit([incoming("e1"), call], marks: marks).dividerRowID == nil)
  }

  @Test func theDividerNamesTheRowOfItsMessage() {
    let marks = marks()
    marks.markRead([incoming("e1")], assistantID: assistantID)
    var message = incoming("e2")
    message.idempotencyKey = "key-2"

    #expect(visit([incoming("e1"), message], marks: marks).dividerRowID == "key-2")
  }

  @Test func messagesArrivingWhileVisibleGetNoDivider() {
    let marks = marks()
    marks.markRead([incoming("e1")], assistantID: assistantID)
    var visit = visit([incoming("e1")], marks: marks)

    visit.place(in: [incoming("e1"), incoming("e2")], lastReadID: "e1")

    #expect(visit.dividerRowID == nil)
  }

  @Test func theDividerStaysInPlaceForTheVisit() {
    let marks = marks()
    marks.markRead([incoming("e1")], assistantID: assistantID)
    var visit = visit([incoming("e1"), incoming("e2")], marks: marks)

    visit.place(in: [incoming("e1"), incoming("e2"), incoming("e3")], lastReadID: "e1")

    #expect(visit.dividerRowID == "e2")
  }

  @Test func leavingMarksEverythingSeenAsRead() {
    let marks = marks()
    marks.markRead([incoming("e1")], assistantID: assistantID)
    var visit = visit([incoming("e1"), incoming("e2")], marks: marks)

    let left = visit.leave()
    #expect(left)
    marks.markRead([incoming("e1"), incoming("e2")], assistantID: assistantID)

    #expect(self.visit([incoming("e1"), incoming("e2")], marks: marks).dividerRowID == nil)
  }

  @Test func onlyAPlacedVisitLeaves() {
    var visit = ConversationVisit()

    let leftUnopened = visit.leave()
    #expect(!leftUnopened)
    visit.open()
    visit.place(in: [incoming("e1")], lastReadID: nil)
    let left = visit.leave()
    #expect(left)
    let leftTwice = visit.leave()
    #expect(!leftTwice)
    #expect(visit.dividerRowID == nil)
  }

  @Test func aVisitWhoseLoadFailedPlacesNothingAndMarksNothingRead() {
    var visit = ConversationVisit()
    visit.open()

    // The fetch failed, so the visit was never placed.
    let left = visit.leave()

    #expect(visit.dividerRowID == nil)
    #expect(!left)
  }

  @Test func aClosedVisitPlacesNoDivider() {
    var visit = ConversationVisit()

    visit.place(in: [incoming("e1"), incoming("e2")], lastReadID: "e1")

    #expect(visit.dividerRowID == nil)
  }

  @Test func messagesReceivedInTheBackgroundAreUnreadOnReturn() {
    let marks = marks()
    marks.markRead([incoming("e1")], assistantID: assistantID)
    var visit = visit([incoming("e1"), incoming("e2")], marks: marks)
    #expect(visit.dividerRowID == "e2")

    // Backgrounding with e2 on screen.
    let left = visit.leave()
    #expect(left)
    marks.markRead([incoming("e1"), incoming("e2")], assistantID: assistantID)
    // Coming back once e3 and e4 arrived.
    visit.open()
    visit.place(
      in: [incoming("e1"), incoming("e2"), incoming("e3"), incoming("e4")],
      lastReadID: marks.lastReadID(assistantID: assistantID))

    #expect(visit.dividerRowID == "e3")
  }

  @Test func returningWithNothingNewShowsNoDivider() {
    let marks = marks()
    marks.markRead([incoming("e1")], assistantID: assistantID)
    var visit = visit([incoming("e1"), incoming("e2")], marks: marks)

    let left = visit.leave()
    #expect(left)
    marks.markRead([incoming("e1"), incoming("e2")], assistantID: assistantID)
    visit.open()
    visit.place(
      in: [incoming("e1"), incoming("e2")], lastReadID: marks.lastReadID(assistantID: assistantID))

    #expect(visit.dividerRowID == nil)
  }

  @Test func readMarksPersistAcrossRelaunch() {
    let suite = "UnreadTests.\(UUID().uuidString)"
    ReadMarks(defaults: UserDefaults(suiteName: suite)!)
      .markRead([incoming("e1"), incoming("e2")], assistantID: assistantID)

    let relaunched = ReadMarks(defaults: UserDefaults(suiteName: suite)!)

    #expect(relaunched.lastReadID(assistantID: assistantID) == "e2")
    #expect(relaunched.lastReadID(assistantID: "as-2") == nil)
  }

  @Test func theReadMarkNeverMovesBack() {
    let marks = marks()
    marks.markRead([incoming("e1"), incoming("e2")], assistantID: assistantID)

    marks.markRead([incoming("e1")], assistantID: assistantID)
    marks.markRead([], assistantID: assistantID)

    #expect(marks.lastReadID(assistantID: assistantID) == "e2")
  }

  @Test func aNewDividerScrollsToItself() {
    #expect(TimelineScroll(lastRowID: (nil, "e3"), dividerRowID: (nil, "e2")) == .divider("e2"))
    #expect(TimelineScroll(lastRowID: ("e3", "e3"), dividerRowID: (nil, "e2")) == .divider("e2"))
  }

  @Test func withoutANewDividerNewRowsScrollToTheBottom() {
    #expect(
      TimelineScroll(lastRowID: (nil, "e3"), dividerRowID: (nil, nil)) == .bottom(animated: false))
    #expect(
      TimelineScroll(lastRowID: ("e3", "e4"), dividerRowID: ("e2", "e2"))
        == .bottom(animated: true))
    #expect(
      TimelineScroll(lastRowID: ("e3", "e4"), dividerRowID: ("e2", nil)) == .bottom(animated: true))
  }

  @Test func nothingChangedKeepsThePosition() {
    #expect(TimelineScroll(lastRowID: ("e3", "e3"), dividerRowID: ("e2", "e2")) == .keep)
    #expect(TimelineScroll(lastRowID: ("e3", "e3"), dividerRowID: ("e2", nil)) == .keep)
  }
}
