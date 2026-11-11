/// What the composer offers for a draft, and while a voice chat is on.
struct ComposerState: Equatable {
  /// One button in the same spot: it dictates into an empty field and sends once there is text.
  enum TrailingButton: Equatable {
    case dictate
    case send
  }

  var draft = ""
  var isInCall = false

  /// Nothing during a call, which listens on its own and starts from the title bar.
  var trailingButton: TrailingButton? {
    if isInCall { return nil }
    return draft.isEmpty ? .dictate : .send
  }

  var isFieldEnabled: Bool { !isInCall }
  var canSend: Bool { TextValidation.isValidMessage(draft) }
}
