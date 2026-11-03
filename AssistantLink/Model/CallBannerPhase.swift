enum CallBannerPhase: Equatable {
  case connecting
  case live
  case muted

  init(state: VoiceCall.State, isMuted: Bool) {
    if isMuted {
      self = .muted
    } else {
      self = state == .connecting ? .connecting : .live
    }
  }
}
