import Foundation

enum UUIDv7 {
  /// The creation time a UUIDv7 carries in its leading 48 bits (Unix milliseconds).
  static func date(fromID id: String) -> Date? {
    let hex = id.replacingOccurrences(of: "-", with: "")
    guard hex.count == 32, hex[hex.index(hex.startIndex, offsetBy: 12)] == "7",
      let milliseconds = UInt64(hex.prefix(12), radix: 16)
    else { return nil }
    return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
  }
}

/// A system event in an Assistant's conversation. The service stores no timeline yet, so the
/// app derives these from the Assistant's Links.
struct TimelineEvent: Equatable, Identifiable {
  let link: Link

  var id: Link.ID { link.id }
  var date: Date? { UUIDv7.date(fromID: link.id) }
}

extension Assistant {
  /// Oldest first; ids are UUIDv7, so ordering by id is creation order.
  var events: [TimelineEvent] {
    links.sorted { $0.id < $1.id }.map(TimelineEvent.init)
  }

  var latestEvent: TimelineEvent? { events.last }
}

enum EventTime {
  /// Messaging-app style: the time for today, the day for this year, else the full date.
  static func short(
    _ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
  ) -> String {
    var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    if calendar.isDate(date, inSameDayAs: now) {
      style = style.hour().minute()
    } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
      style = style.month(.abbreviated).day()
    } else {
      style = style.year(.twoDigits).month(.defaultDigits).day()
    }
    return date.formatted(style)
  }
}
