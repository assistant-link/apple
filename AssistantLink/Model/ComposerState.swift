/// What the composer offers for a draft, and while a voice chat is on.
struct ComposerState: Equatable {
  enum TrailingButton: Equatable {
    case voiceChat
    case send
  }

  var draft = ""
  var isInCall = false

  /// The red voice button becomes Send once there is text; neither shows during a call.
  var trailingButton: TrailingButton? {
    if isInCall { return nil }
    return draft.isEmpty ? .voiceChat : .send
  }

  var showsDictation: Bool { !isInCall }
  var isFieldEnabled: Bool { !isInCall }
  var canSend: Bool { TextValidation.isValidMessage(draft) }
}
