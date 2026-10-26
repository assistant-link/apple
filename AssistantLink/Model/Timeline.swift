import Foundation

enum UUIDv7 {
  /// A new id for `date`: 48 bits of Unix milliseconds, then the version and variant bits
  /// around 74 random bits.
  static func make(at date: Date = .now, random: (UInt64, UInt64)? = nil) -> String {
    let first = random?.0 ?? .random(in: 0...UInt64.max)
    let second = random?.1 ?? .random(in: 0...UInt64.max)
    let milliseconds = UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded()))
    let high: UInt64 = (milliseconds & 0xFFFF_FFFF_FFFF) << 16 | 0x7000 | (first & 0x0FFF)
    let low: UInt64 = 0x8000_0000_0000_0000 | (second & 0x3FFF_FFFF_FFFF_FFFF)
    let hex = String(format: "%016llx%016llx", high, low)
    let groups = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4)]
    let rest = [hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
    return (groups + rest).joined(separator: "-")
  }

  /// The creation time a UUIDv7 carries in its leading 48 bits (Unix milliseconds).
  static func date(fromID id: String) -> Date? {
    let hex = id.replacingOccurrences(of: "-", with: "")
    guard hex.count == 32, hex[hex.index(hex.startIndex, offsetBy: 12)] == "7",
      let milliseconds = UInt64(hex.prefix(12), radix: 16)
    else { return nil }
    return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
  }
}

/// The events of one Assistant's conversation loaded so far, oldest first.
struct Timeline: Equatable, Sendable {
  var events: [Event] = []
  /// Whether events older than the first loaded one exist.
  var hasMore = false

  /// Adds an event the service just stored, or replaces the loaded one with the same id.
  mutating func receive(_ event: Event) {
    if let index = events.firstIndex(where: { $0.id == event.id }) {
      events[index] = event
    } else {
      events.append(event)
    }
  }

  /// Replaces a loaded event; an event that isn't loaded stays out.
  mutating func update(_ event: Event) {
    if let index = events.firstIndex(where: { $0.id == event.id }) {
      events[index] = event
    }
  }

  /// Takes the latest page. If it shares an event with the loaded ones, they merge by id and
  /// the older loaded events stay; otherwise the page replaces them.
  mutating func refetch(with page: EventPage) {
    let pageIDs = Set(page.events.map(\.id))
    guard let overlap = events.firstIndex(where: { pageIDs.contains($0.id) }) else {
      events = page.events
      hasMore = page.hasMore
      return
    }
    let older = Array(events[..<overlap])
    let newer = events[overlap...].filter { !pageIDs.contains($0.id) }
    events = older + page.events + newer
    if overlap == 0 {
      hasMore = page.hasMore
    }
  }

  /// Adds the page that precedes the first loaded event.
  mutating func prepend(_ page: EventPage) {
    let loadedIDs = Set(events.map(\.id))
    events = page.events.filter { !loadedIDs.contains($0.id) } + events
    hasMore = page.hasMore
  }
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
