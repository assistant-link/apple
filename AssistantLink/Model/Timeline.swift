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

  /// The events, then the outgoing messages a reload has not already stored. The messages of a
  /// voice chat show in its transcript instead. `isInCall` is whether a voice chat with this
  /// Assistant is on now: the service marks only the user's speech `via: voice`, so the
  /// Assistant's spoken replies are told apart only by coming after its `call_started` or
  /// `voice_call`. Those alone can't tell, because the end of the call can be lost.
  func rows(isInCall: Bool = false) -> [TimelineRow] {
    let stored = Set(events.compactMap(\.idempotencyKey))
    let groups = callGroups(isInCall: isInCall)
    let live = isInCall ? openCallIndices : 0..<0
    let sessionEnds = Set(groups.sessionEnds.values)
    let shown = events.indices.filter { groups.folded[$0] == nil && !sessionEnds.contains($0) }
    let eventRows = shown.map { index in
      TimelineRow(
        id: Self.rowID(of: events[index]), content: .event(events[index]),
        showsTimeCaption: events[index].type == .textMessage
          && showsTimeCaption(beforeEventAt: index),
        replyTarget: live.contains(index) ? nil : ReplyTarget(events[index]))
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
    rows().last?.id
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
    let folded = callGroups(isInCall: false).folded
    return unread.map { Self.rowID(of: events[folded[$0] ?? $0]) }
  }

  /// How the call events gather the conversation's messages.
  private struct CallGroups {
    /// The indices of the text messages said in a voice chat, each with the index of the
    /// chat's entry: its `call_ended`, or its `voice_call`.
    var folded: [Int: Int] = [:]
    /// The index of each `voice_call` whose `call_ended` is loaded, which shows no row of its own:
    /// the service still writes `call_started` and `call_ended` for older apps.
    var sessionEnds: [Int: Int] = [:]
    /// The index of the `voice_call` of the call that is on now.
    var live: Int?
  }

  /// A `call_started` open when a `voice_call` comes, or the first one after it, is that call's
  /// own.
  private func callGroups(isInCall: Bool) -> CallGroups {
    var groups = CallGroups()
    var sessions: [Int] = []
    var start: Int?
    // The `voice_call` whose `call_ended` has not come yet, and whether its `call_started` has.
    var session: (index: Int, hasStart: Bool)?
    for (index, event) in events.enumerated() {
      switch event.type {
      case .voiceCall:
        sessions.append(index)
        session = (index, start != nil)
        start = nil
      case .callStarted:
        if let open = session, !open.hasStart {
          session = (open.index, true)
        } else {
          session = nil
          start = index
        }
      case .callEnded:
        if let open = session {
          groups.sessionEnds[open.index] = index
        } else if let start {
          for message in start + 1..<index where events[message].type == .textMessage {
            groups.folded[message] = index
          }
        }
        session = nil
        start = nil
      default:
        break
      }
    }
    for (position, index) in sessions.enumerated() {
      let next = position + 1 < sessions.count ? sessions[position + 1] : events.endIndex
      let end = groups.sessionEnds[index] ?? next
      let endedAt = events[index].voiceCall?.endedAt
      if endedAt == nil, groups.sessionEnds[index] == nil {
        // An end the service never got would otherwise hide every later message.
        guard isInCall, position == sessions.count - 1 else { continue }
        groups.live = index
      }
      for message in index + 1..<end where events[message].type == .textMessage {
        if let endedAt, events[message].createdAt > endedAt { break }
        groups.folded[message] = index
      }
    }
    return groups
  }

  /// The `voice_call` entry of the call that is on now, which counts up and opens the call.
  func liveVoiceCallID(isInCall: Bool) -> Event.ID? {
    callGroups(isInCall: isInCall).live.map { events[$0].id }
  }

  /// The indices after a `call_started` that no `call_ended` follows yet.
  private var openCallIndices: Range<Int> {
    guard let start = events.lastIndex(where: { $0.type == .callStarted }),
      !events[start...].contains(where: { $0.type == .callEnded })
    else { return 0..<0 }
    return start + 1..<events.endIndex
  }

  /// What the bubble of a reply to `id` quotes, or `nil` when the conversation has no such message.
  func quote(forReplyTo id: String) -> ReplyQuote? {
    guard let index = events.firstIndex(where: { $0.id == id }) else {
      return hasMore ? .earlier : nil
    }
    let event = events[index]
    guard event.type == .textMessage else { return nil }
    guard !event.deleted, let text = event.text else { return .deleted }
    let folded = callGroups(isInCall: false).folded
    return .message(text: text, rowID: Self.rowID(of: events[folded[index] ?? index]))
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

  /// The voice chat of a `voice_call`, whose lines are the call's transcript entries.
  func voiceChat(of event: Event) -> VoiceChatRecord {
    let call = event.voiceCall
    let startedAt = call?.startedAt ?? event.createdAt
    var seconds = call?.seconds
    if seconds == nil, call?.endedAt == nil,
      let index = events.firstIndex(where: { $0.id == event.id }),
      let end = callGroups(isInCall: false).sessionEnds[index]
    {
      // Its `call_ended` can come before the update with the end.
      seconds = max(0, Int(events[end].createdAt.timeIntervalSince(startedAt)))
    }
    return VoiceChatRecord(
      id: event.id, startedAt: startedAt, seconds: seconds, lines: [], callID: call?.callID)
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
  /// The id of the `call_ended` or `voice_call` event.
  let id: String
  let startedAt: Date?
  let seconds: Int?
  var lines: [TranscriptLine]
  /// The call whose transcript entries are the lines; `nil` for a chat from before calls were
  /// sessions, whose lines are its messages.
  var callID: String?
}

extension CallTranscriptEntry {
  var line: TranscriptLine? {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return TranscriptLine(id: id, text: text, isFromUser: speaker == .user)
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
