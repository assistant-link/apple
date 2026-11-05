enum CallBannerPhase: Equatable {
  case connecting
  case live
  case muted
  /// Listening gave up after repeated recognizer failures; a tap tries again.
  case notListening

  init(state: VoiceCall.State, isMuted: Bool, listeningFailed: Bool) {
    if isMuted {
      self = .muted
    } else if listeningFailed && state != .speaking {
      self = .notListening
    } else {
      self = state == .connecting ? .connecting : .live
    }
  }
}

extension CallBannerPhase {
  var accessibilityValue: String {
    switch self {
    case .connecting: "Connecting"
    case .live: "Live"
    case .muted: "Muted"
    case .notListening: "Not listening"
    }
  }
}
