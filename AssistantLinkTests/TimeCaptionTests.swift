import Foundation
import Testing

@testable import AssistantLink

struct TimeCaptionTests {
  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    Self.calendar.date(
      from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
  }

  private func text(_ date: Date, now: Date) -> String {
    TimeCaption.text(
      for: date, now: now, calendar: Self.calendar, locale: Locale(identifier: "en_GB"))
  }

  @Test func todayShowsTheTime() {
    #expect(text(date(21, 8, 5), now: date(21, 18, 0)) == "Today 08:05")
  }

  @Test func yesterdayShowsTheTime() {
    #expect(text(date(20, 8, 5), now: date(21, 0, 30)) == "Yesterday 08:05")
  }

  @Test func olderDatesShowTheDateAndTime() {
    let result = text(date(14, 9, 12), now: date(21, 18, 0))
    #expect(result.contains("14"))
    #expect(result.contains("09:12"))
    #expect(!result.contains("Today") && !result.contains("Yesterday"))
  }
}
