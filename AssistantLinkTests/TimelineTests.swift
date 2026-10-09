import Foundation
import Testing

@testable import AssistantLink

struct TimelineTests {
  private func link(_ id: String, status: Link.Status = .notPaired) -> Link {
    Link(id: id, label: nil, status: status, lastActiveAt: nil)
  }

  private func assistant(links: [Link]) -> Assistant {
    Assistant(
      id: "01a11a4e-0771-7baf-8a8b-2f8f3f86e219", name: "Hermes", avatar: "avatar-3",
      status: .offline, links: links)
  }

  @Test func uuidv7IdsCarryTheirCreationTime() {
    #expect(
      UUIDv7.date(fromID: "01a11a4e-0a6a-7edf-996d-7e8f06fc11ed")
        == Date(timeIntervalSince1970: 1_791_442_684.522))
  }

  @Test(arguments: ["l-1", "01a11a4e-0a6a-4edf-996d-7e8f06fc11ed", "01a11a4e0a6a"])
  func otherIdsHaveNoCreationTime(id: String) {
    #expect(UUIDv7.date(fromID: id) == nil)
  }

  @Test func eachLinkAddsALinkCreatedEventOldestFirst() {
    let older = link("01a11a4e-0a6a-7edf-996d-7e8f06fc11ed")
    let newer = link("01a11a4e-42ee-7ebf-b82d-d195d2252d57", status: .online)

    let events = assistant(links: [newer, older]).events

    #expect(events.map(\.link) == [older, newer])
    #expect(events.first?.date == Date(timeIntervalSince1970: 1_791_442_684.522))
  }

  @Test func theLatestEventIsTheNewestLink() {
    let older = link("01a11a4e-0a6a-7edf-996d-7e8f06fc11ed")
    let newer = link("01a11a4e-42ee-7ebf-b82d-d195d2252d57")

    #expect(assistant(links: [older, newer]).latestEvent?.link == newer)
    #expect(assistant(links: []).latestEvent == nil)
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
