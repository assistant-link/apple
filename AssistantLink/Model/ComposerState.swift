/// What the composer offers for a draft, and while a voice chat is on.
struct ComposerState: Equatable {
  enum TrailingButton: Equatable {
    case send
  }

  var draft = ""
  var isInCall = false

  /// Send shows once there is text, and never during a call. The call starts from the title bar.
  var trailingButton: TrailingButton? {
    if isInCall || draft.isEmpty { return nil }
    return .send
  }

  var showsDictation: Bool { !isInCall }
  var isFieldEnabled: Bool { !isInCall }
  var canSend: Bool { TextValidation.isValidMessage(draft) }
}
