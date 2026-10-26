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

/// A message the user sent from this app that the service has not stored yet.
struct OutgoingMessage: Equatable, Identifiable, Sendable {
  enum State: Equatable, Sendable {
    case sending
    case failed
  }

  let assistantID: String
  let idempotencyKey: String
  let text: String
  let createdAt: Date
  var state = State.sending
  /// The timeline's `received` count when the message was queued; later events mean the message
  /// is no longer the newest, which the device and server clocks could not tell reliably.
  var receivedBefore = 0

  var id: String { idempotencyKey }
}

/// The caption under the latest user message.
enum MessageCaption: Equatable, Sendable {
  case sending
  case sent
  case delivered
  case notDelivered

  var text: String {
    switch self {
    case .sending: "Sending…"
    case .sent: "Sent"
    case .delivered: "Delivered"
    case .notDelivered: "Not Delivered"
    }
  }
}

/// The events of one Assistant's conversation loaded so far, oldest first.
struct Timeline: Equatable, Sendable {
  var events: [Event] = []
  /// Whether events older than the first loaded one exist.
  var hasMore = false
  /// Messages sent from this app and not stored yet, oldest first; they show after the events.
  var outgoing: [OutgoingMessage] = []
  /// How many events were added to a loaded conversation; it only grows.
  var received = 0

  /// The id of the latest user message, an outgoing one or a stored event.
  var latestUserMessageID: String? {
    outgoing.last?.id
      ?? events.last(where: { $0.type == .textMessage && $0.sender == .user })?.id
  }

  /// The caption of the message `id`; only the latest user message has one.
  func caption(forMessageID id: String) -> MessageCaption? {
    guard id == latestUserMessageID else { return nil }
    if let message = outgoing.first(where: { $0.id == id }) {
      return message.state == .sending ? .sending : .notDelivered
    }
    switch events.first(where: { $0.id == id })?.deliveryStatus {
    case .sent: return .sent
    case .delivered: return .delivered
    case nil: return nil
    }
  }

  /// Stores the event the service answered a post with, unless the live connection delivered
  /// it first, which is at least as current. Returns whether the event was new.
  mutating func store(_ event: Event) -> Bool {
    let isNew = !events.contains { $0.id == event.id }
    if isNew {
      // A retry the service had already stored answers with that older event; ids sort by time.
      events.insert(event, at: events.firstIndex { $0.id > event.id } ?? events.endIndex)
      received += 1
    }
    removeOutgoing(matching: event)
    return isNew
  }

  private mutating func removeOutgoing(matching event: Event) {
    guard let key = event.idempotencyKey else { return }
    outgoing.removeAll { $0.idempotencyKey == key }
  }

  /// Adds an event the service just stored, or replaces the loaded one with the same id.
  mutating func receive(_ event: Event) {
    removeOutgoing(matching: event)
    if let index = events.firstIndex(where: { $0.id == event.id }) {
      events[index] = event
    } else {
      events.append(event)
      received += 1
    }
  }

  mutating func update(_ event: Event) {
    if let index = events.firstIndex(where: { $0.id == event.id }) {
      events[index] = event
    }
  }

  /// Takes the latest page. If it shares an event with the loaded ones, they merge by id and
  /// the older loaded events stay; otherwise the page replaces them, except the loaded events
  /// after it, which the live connection delivered while the page loaded.
  mutating func refetch(with page: EventPage) {
    let loaded = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    if !events.isEmpty {
      received += page.events.filter { loaded[$0.id] == nil }.count
    }
    // The page can be older than a live copy, and these fields only move forward.
    let fetched = page.events.map { event in
      guard let current = loaded[event.id] else { return event }
      if current.deleted && !event.deleted { return current }
      var merged = event
      if current.deliveryStatus == .delivered { merged.deliveryStatus = .delivered }
      return merged
    }
    let pageIDs = Set(fetched.map(\.id))
    guard let overlap = events.firstIndex(where: { pageIDs.contains($0.id) }) else {
      let newer = fetched.last.map { last in events.filter { $0.id > last.id } } ?? events
      events = fetched + newer
      hasMore = page.hasMore
      return
    }
    let older = Array(events[..<overlap])
    let newer = events[overlap...].filter { !pageIDs.contains($0.id) }
    events = older + fetched + newer
    if overlap == 0 {
      hasMore = page.hasMore
    }
  }

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
