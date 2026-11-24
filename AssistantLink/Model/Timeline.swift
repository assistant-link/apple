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
  var via: Event.Via?
  var replyTo: String?

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

/// One row of a conversation: a stored event, or a message the service has not stored yet.
struct TimelineRow: Equatable, Identifiable, Sendable {
  enum Content: Equatable, Sendable {
    case event(Event)
    case outgoing(OutgoingMessage)
  }

  /// A message sent from this app keeps its idempotency key once stored, so the list moves the
  /// same row instead of replacing it, which would make the list jump.
  let id: String
  let content: Content
  let showsTimeCaption: Bool
  /// What a reply to this row answers; `nil` when it can't be replied to.
  var replyTarget: ReplyTarget?
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
    case .unknown, nil: return nil
    }
  }

  static func rowID(of event: Event) -> String {
    event.idempotencyKey ?? event.id
  }

  /// The events, then the outgoing messages a reload has not already stored. The messages of an
  /// ended voice chat show in its transcript instead.
  var rows: [TimelineRow] {
    let stored = Set(events.compactMap(\.idempotencyKey))
    let folded = foldedIndices
    let eventRows = events.indices.filter { folded[$0] == nil }.map { index in
      TimelineRow(
        id: Self.rowID(of: events[index]), content: .event(events[index]),
        showsTimeCaption: events[index].type == .textMessage
          && showsTimeCaption(beforeEventAt: index),
        replyTarget: ReplyTarget(events[index]))
    }
    let outgoingRows = outgoing.indices.filter { !stored.contains(outgoing[$0].id) }.map { index in
      TimelineRow(
        id: outgoing[index].id, content: .outgoing(outgoing[index]),
        showsTimeCaption: showsTimeCaption(beforeOutgoingAt: index))
    }
    return eventRows + outgoingRows
  }

  /// The id of the last row, which a reload that stored every outgoing message leaves to the events.
  var lastRowID: String? {
    rows.last?.id
  }

  func showsTimeCaption(beforeEventAt index: Int) -> Bool {
    TimeCaption.isShown(
      for: events[index].createdAt, after: index > 0 ? events[index - 1].createdAt : nil)
  }

  func showsTimeCaption(beforeOutgoingAt index: Int) -> Bool {
    let previous = index > 0 ? outgoing[index - 1].createdAt : events.last?.createdAt
    return TimeCaption.isShown(for: outgoing[index].createdAt, after: previous)
  }

  /// The row of the first incoming message after `lastReadID`. A message folded into an ended
  /// voice chat shows as that chat's entry.
  func firstUnreadRowID(after lastReadID: String) -> String? {
    let unread = events.firstIndex {
      $0.id > lastReadID && $0.type == .textMessage && $0.sender == .assistant
    }
    let folded = foldedIndices
    return unread.map { Self.rowID(of: events[folded[$0] ?? $0]) }
  }

  /// The indices of the text messages between a `call_started` and the `call_ended` after it,
  /// each with the index of that `call_ended`.
  private var foldedIndices: [Int: Int] {
    var folded: [Int: Int] = [:]
    var start: Int?
    for (index, event) in events.enumerated() {
      switch event.type {
      case .callStarted:
        start = index
      case .callEnded:
        if let start {
          for message in start + 1..<index where events[message].type == .textMessage {
            folded[message] = index
          }
        }
        start = nil
      default:
        break
      }
    }
    return folded
  }

  /// What the bubble of a reply to `id` quotes, or `nil` when the conversation has no such message.
  func quote(forReplyTo id: String) -> ReplyQuote? {
    guard let index = events.firstIndex(where: { $0.id == id }) else {
      return hasMore ? .earlier : nil
    }
    let event = events[index]
    guard event.type == .textMessage else { return nil }
    guard !event.deleted, let text = event.text else { return .deleted }
    return .message(text: text, rowID: Self.rowID(of: events[foldedIndices[index] ?? index]))
  }

  /// The voice chat that `event`, a `call_ended`, ended, with the messages since its start.
  func voiceChat(endedBy event: Event) -> VoiceChatRecord {
    let before = events.prefix(while: { $0.id != event.id })
    let start = before.lastIndex(where: { $0.type == .callStarted })
    let lines = start.map { before[($0 + 1)...].compactMap(Self.transcriptLine) } ?? []
    return VoiceChatRecord(
      id: event.id, startedAt: start.map { events[$0].createdAt },
      seconds: voiceChatSeconds(endedBy: event), lines: lines)
  }

  private static func transcriptLine(_ event: Event) -> TranscriptLine? {
    guard event.type == .textMessage, !event.deleted, let text = event.text else { return nil }
    return TranscriptLine(id: event.id, text: text, isFromUser: event.sender == .user)
  }

  /// The seconds a voice chat lasted, from the latest `call_started` before its `call_ended`.
  func voiceChatSeconds(endedBy event: Event) -> Int? {
    guard
      let started = events.prefix(while: { $0.id != event.id })
        .last(where: { $0.type == .callStarted })
    else { return nil }
    return max(0, Int(event.createdAt.timeIntervalSince(started.createdAt)))
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

/// An ended voice chat, which its timeline entry opens.
struct VoiceChatRecord: Equatable, Identifiable, Sendable {
  /// The id of the `call_ended` event.
  let id: String
  let startedAt: Date?
  let seconds: Int?
  let lines: [TranscriptLine]
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
