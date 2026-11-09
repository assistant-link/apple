import Foundation
import Testing

@testable import AssistantLink

extension Event {
  static func stub(_ id: String, assistantID: String = "as-1", text: String? = nil) -> Event {
    Event(
      id: id, assistantID: assistantID, type: .textMessage, sender: .assistant,
      createdAt: Date(timeIntervalSince1970: 0), text: text ?? id)
  }
}

struct UUIDv7Tests {
  @Test func uuidv7IdsCarryTheirCreationTime() {
    #expect(
      UUIDv7.date(fromID: "01a11a4e-0a6a-7edf-996d-7e8f06fc11ed")
        == Date(timeIntervalSince1970: 1_791_442_684.522))
  }

  @Test(arguments: ["l-1", "01a11a4e-0a6a-4edf-996d-7e8f06fc11ed", "01a11a4e0a6a"])
  func otherIdsHaveNoCreationTime(id: String) {
    #expect(UUIDv7.date(fromID: id) == nil)
  }

  @Test func generatedIdsAreVersion7WithTheRandomBitsAfterTheTime() {
    let epoch = Date(timeIntervalSince1970: 0)

    #expect(UUIDv7.make(at: epoch, random: (0, 0)) == "00000000-0000-7000-8000-000000000000")
    #expect(
      UUIDv7.make(at: epoch, random: (.max, .max)) == "00000000-0000-7fff-bfff-ffffffffffff")
  }

  @Test func generatedIdsCarryTheirCreationTime() {
    let date = Date(timeIntervalSince1970: 1_791_442_684.522)

    let id = UUIDv7.make(at: date)

    #expect(UUIDv7.date(fromID: id) == date)
  }

  @Test func generatedIdsAreLowercaseAndUnique() {
    let ids = (0..<100).map { _ in UUIDv7.make() }

    #expect(Set(ids).count == 100)
    for id in ids {
      #expect(id.count == 36)
      #expect(id == id.lowercased())
      #expect("89ab".contains(id[id.index(id.startIndex, offsetBy: 19)]))
      #expect(id[id.index(id.startIndex, offsetBy: 14)] == "7")
    }
  }
}

struct TimelineTests {
  private func loaded(_ ids: [String], hasMore: Bool = false) -> Timeline {
    Timeline(events: ids.map { .stub($0) }, hasMore: hasMore)
  }

  private func page(_ ids: [String], hasMore: Bool = false) -> EventPage {
    EventPage(events: ids.map { .stub($0) }, hasMore: hasMore)
  }

  @Test func receivedEventsAreAppendedOrReplacedById() {
    var timeline = loaded(["a", "b"])

    timeline.receive(.stub("c"))
    timeline.receive(.stub("a", text: "changed"))

    #expect(timeline.events.map(\.id) == ["a", "b", "c"])
    #expect(timeline.events.first?.text == "changed")
  }

  @Test func updatesReplaceOnlyLoadedEvents() {
    var timeline = loaded(["a", "b"])

    timeline.update(.stub("b", text: "changed"))
    timeline.update(.stub("z"))

    #expect(timeline.events.map(\.id) == ["a", "b"])
    #expect(timeline.events.last?.text == "changed")
  }

  @Test func refetchMergesByIdWhenThePageOverlaps() {
    var timeline = loaded(["a", "b", "c"], hasMore: true)
    var changed = Event.stub("c")
    changed.deliveryStatus = .delivered

    timeline.refetch(
      with: EventPage(events: [.stub("b"), changed, .stub("d")], hasMore: false))

    #expect(timeline.events.map(\.id) == ["a", "b", "c", "d"])
    #expect(timeline.events[2].deliveryStatus == .delivered)
    #expect(timeline.hasMore)
  }

  @Test func refetchKeepsLoadedEventsTheServiceDidNotReturnYet() {
    var timeline = loaded(["a", "b", "e"])

    timeline.refetch(with: page(["b", "c", "d"]))

    #expect(timeline.events.map(\.id) == ["a", "b", "c", "d", "e"])
  }

  @Test func refetchReachingBeyondTheOldestLoadedEventTakesThePagesHasMore() {
    var timeline = loaded(["b", "c"])

    timeline.refetch(with: page(["a", "b", "c", "d"], hasMore: true))

    #expect(timeline.events.map(\.id) == ["a", "b", "c", "d"])
    #expect(timeline.hasMore)
  }

  @Test func refetchReplacesTheEventsWhenThePageDoesNotOverlap() {
    var timeline = loaded(["a", "b"])

    timeline.refetch(with: page(["x", "y"], hasMore: true))

    #expect(timeline.events.map(\.id) == ["x", "y"])
    #expect(timeline.hasMore)
  }

  @Test func refetchNeverDowngradesADeliveredMessage() {
    var delivered = Event.stub("b")
    delivered.deliveryStatus = .delivered
    var timeline = Timeline(events: [.stub("a"), delivered])
    var stale = Event.stub("b")
    stale.deliveryStatus = .sent

    timeline.refetch(with: EventPage(events: [.stub("a"), stale], hasMore: false))

    #expect(timeline.events[1].deliveryStatus == .delivered)
  }

  @Test func refetchKeepsADeletedMessageDeleted() {
    var deleted = Event.stub("b")
    deleted.deleted = true
    deleted.text = nil
    var timeline = Timeline(events: [.stub("a"), deleted])

    timeline.refetch(with: page(["a", "b"]))

    #expect(timeline.events[1].deleted)
    #expect(timeline.events[1].text == nil)
  }

  @Test func refetchKeepsLiveEventsNewerThanAPageWithoutOverlap() {
    var timeline = loaded(["e-3"])

    timeline.refetch(with: page(["e-1", "e-2"]))

    #expect(timeline.events.map(\.id) == ["e-1", "e-2", "e-3"])
  }

  @Test func aStoredEventTheServiceHadAlreadyKeptItsPlaceById() {
    var timeline = loaded(["a", "c", "d"])

    let isNew = timeline.store(.stub("b"))

    #expect(isNew)
    #expect(timeline.events.map(\.id) == ["a", "b", "c", "d"])
    let isStoredAgain = timeline.store(.stub("b"))
    #expect(!isStoredAgain)
    #expect(timeline.events.map(\.id) == ["a", "b", "c", "d"])
  }

  @Test func prependAddsTheEarlierPageWithoutDuplicates() {
    var timeline = loaded(["c", "d"], hasMore: true)

    timeline.prepend(page(["a", "b", "c"]))

    #expect(timeline.events.map(\.id) == ["a", "b", "c", "d"])
    #expect(!timeline.hasMore)
  }
}

struct EventTimeTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()
  private let locale = Locale(identifier: "en_US_POSIX")
  private let now = Date(timeIntervalSince1970: 1_791_469_920)  // 2026-10-08 14:32 UTC

  private func format(_ date: Date) -> String {
    EventTime.short(date, now: now, calendar: calendar, locale: locale)
  }

  @Test func todayShowsTheTime() {
    #expect(format(now.addingTimeInterval(-3600)) == "1:32\u{202F}PM")
  }

  @Test func earlierThisYearShowsMonthAndDay() {
    #expect(format(Date(timeIntervalSince1970: 1_790_726_400)) == "Sep 30")
  }

  @Test func earlierYearsShowTheFullDate() {
    #expect(format(Date(timeIntervalSince1970: 1_759_276_800)) == "10/1/25")
  }
}

struct TimelineTimeCaptionTests {
  private func stub(_ id: String, at seconds: TimeInterval) -> Event {
    Event(
      id: id, assistantID: "as-1", type: .textMessage, sender: .assistant,
      createdAt: Date(timeIntervalSince1970: seconds), text: id)
  }

  private func outgoing(_ key: String, at seconds: TimeInterval) -> OutgoingMessage {
    OutgoingMessage(
      assistantID: "as-1", idempotencyKey: key, text: key,
      createdAt: Date(timeIntervalSince1970: seconds))
  }

  @Test func eventsShowACaptionAfterAPause() {
    let timeline = Timeline(events: [
      stub("e-1", at: 0), stub("e-2", at: 60), stub("e-3", at: 7_200),
    ])

    #expect(timeline.showsTimeCaption(beforeEventAt: 0))
    #expect(!timeline.showsTimeCaption(beforeEventAt: 1))
    #expect(timeline.showsTimeCaption(beforeEventAt: 2))
  }

  @Test func anOutgoingMessageFollowsTheLatestEventOrThePreviousOutgoingMessage() {
    let timeline = Timeline(
      events: [stub("e-1", at: 0)],
      outgoing: [outgoing("k-1", at: 60), outgoing("k-2", at: 9_000)])

    #expect(!timeline.showsTimeCaption(beforeOutgoingAt: 0))
    #expect(timeline.showsTimeCaption(beforeOutgoingAt: 1))
  }

  @Test func anOutgoingMessageInAnEmptyTimelineHasACaption() {
    let timeline = Timeline(outgoing: [outgoing("k-1", at: 0)])

    #expect(timeline.showsTimeCaption(beforeOutgoingAt: 0))
  }
}

struct TimelineRowTests {
  private let key = "k-1"

  private func sent(_ id: String) -> Event {
    Event(
      id: id, assistantID: "as-1", type: .textMessage, sender: .user,
      createdAt: Date(timeIntervalSince1970: 60), idempotencyKey: key, text: "Hi")
  }

  private func sending() -> Timeline {
    Timeline(
      events: [.stub("e-1")],
      outgoing: [
        OutgoingMessage(
          assistantID: "as-1", idempotencyKey: key, text: "Hi",
          createdAt: Date(timeIntervalSince1970: 60))
      ])
  }

  @Test func aSentMessageKeepsItsRowOnceTheServiceStoresIt() {
    var timeline = sending()
    let before = timeline.rows.map(\.id)

    _ = timeline.store(sent("e-2"))

    #expect(timeline.rows.map(\.id) == before)
    #expect(timeline.rows.map(\.id) == ["e-1", key])
  }

  @Test func theLastRowStaysTheSameOnceTheServiceStoresIt() {
    var timeline = sending()
    let before = timeline.lastRowID

    timeline.receive(sent("e-2"))

    #expect(before == key)
    #expect(timeline.lastRowID == key)
  }

  @Test func anOutgoingMessageAReloadAlreadyStoredShowsOnce() {
    var timeline = sending()

    timeline.refetch(with: EventPage(events: [.stub("e-1"), sent("e-2")], hasMore: false))

    #expect(timeline.rows.map(\.id) == ["e-1", key])
    #expect(timeline.rows.last?.content == .event(sent("e-2")))
  }

  @Test func eventsFromElsewhereKeepTheirId() {
    #expect(Timeline(events: [.stub("e-1")]).rows.map(\.id) == ["e-1"])
  }
}
