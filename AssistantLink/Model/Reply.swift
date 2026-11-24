/// A chat message the user picked to answer.
struct ReplyTarget: Equatable, Sendable {
  let eventID: String
  let text: String
  let isFromUser: Bool

  func title(assistantName: String) -> String {
    isFromUser ? "Replying to you" : "Replying to \(assistantName)"
  }
}

extension ReplyTarget {
  /// Only chat text messages; a voice chat and what was said in it can't be answered.
  init?(_ event: Event) {
    guard event.type == .textMessage, !event.deleted, let text = event.text,
      event.sender == .user || event.sender == .assistant
    else { return nil }
    self.init(eventID: event.id, text: text, isFromUser: event.sender == .user)
  }
}

/// What the bubble of a reply shows of the message it answers.
enum ReplyQuote: Equatable, Sendable {
  /// `rowID` is the row a tap scrolls to: the message's own, or the voice chat it was said in.
  case message(text: String, rowID: String)
  case deleted
  /// Older than the loaded pages, which a tap loads until it is there.
  case earlier

  var text: String {
    switch self {
    case .message(let text, _): text
    case .deleted: "This message was deleted"
    case .earlier: "Earlier message"
    }
  }

  var isTappable: Bool { self != .deleted }
}

/// The composer's words and the message they answer, if the user picked one.
struct MessageDraft: Equatable {
  var text = ""
  var replyTarget: ReplyTarget?

  /// Empties the draft for sending.
  mutating func take() -> (text: String, replyTo: String?) {
    defer { self = MessageDraft() }
    return (text, replyTarget?.eventID)
  }
}
