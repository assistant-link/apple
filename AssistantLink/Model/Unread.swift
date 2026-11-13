import Foundation

/// The newest event read in each conversation, kept on the device.
struct ReadMarks {
  static let key = "lastReadEventIDs"

  var defaults: UserDefaults = .standard

  func lastReadID(assistantID: Assistant.ID) -> String? {
    marks[assistantID]
  }

  /// Everything loaded counts as seen. Ids sort by time, so the mark only moves forward.
  func markRead(_ events: [Event], assistantID: Assistant.ID) {
    guard let newest = events.last?.id, newest > (lastReadID(assistantID: assistantID) ?? "")
    else { return }
    var updated = marks
    updated[assistantID] = newest
    defaults.set(updated, forKey: Self.key)
  }

  private var marks: [String: String] {
    defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
  }
}

/// One visit to a conversation, from opening it or returning to the app until leaving either.
struct ConversationVisit: Equatable {
  /// The row of the first incoming message that was unread when the visit's events loaded.
  private(set) var dividerRowID: String?
  private(set) var isOpen = false
  private var isPlaced = false

  mutating func open() {
    self = ConversationVisit()
    isOpen = true
  }

  /// Only the first call of a visit places the divider, so messages arriving while the user
  /// looks get none. A conversation never read on this device has no divider.
  mutating func place(in events: [Event], lastReadID: String?) {
    guard isOpen, !isPlaced else { return }
    isPlaced = true
    guard let lastReadID else { return }
    let unread = events.first {
      $0.id > lastReadID && $0.type == .textMessage && $0.sender == .assistant
    }
    dividerRowID = unread.map(Timeline.rowID(of:))
  }

  /// Returns whether the visit was open, in which case what it showed now counts as read.
  mutating func leave() -> Bool {
    defer { self = ConversationVisit() }
    return isOpen
  }
}

/// Where the conversation scrolls when its last row or its divider changes.
enum TimelineScroll: Equatable {
  case keep
  case bottom(animated: Bool)
  /// The divider row to the top. The scroll view stops at the bottom instead when the divider
  /// is already in the last screenful, so the unread messages that fit keep the usual position.
  case divider(String)

  init(
    lastRowID: (old: String?, new: String?), dividerRowID: (old: String?, new: String?)
  ) {
    if let divider = dividerRowID.new, divider != dividerRowID.old {
      self = .divider(divider)
    } else if lastRowID.new != lastRowID.old {
      // The first load lands at the bottom without a visible scroll.
      self = .bottom(animated: lastRowID.old != nil)
    } else {
      self = .keep
    }
  }
}
