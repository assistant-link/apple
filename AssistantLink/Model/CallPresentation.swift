/// What a conversation screen shows of the voice chat: only a call with its own Assistant counts.
struct CallPresentation: Equatable {
  /// `nil` when there is no call with this Assistant.
  let bannerPhase: CallBannerPhase?

  init(
    state: VoiceCall.State, isMuted: Bool, callAssistantID: Assistant.ID?,
    assistantID: Assistant.ID
  ) {
    if state == .idle || callAssistantID != assistantID {
      bannerPhase = nil
    } else {
      bannerPhase = CallBannerPhase(state: state, isMuted: isMuted)
    }
  }

  @MainActor
  init(_ call: VoiceCall, assistantID: Assistant.ID) {
    self.init(
      state: call.state, isMuted: call.isMuted, callAssistantID: call.assistantID,
      assistantID: assistantID)
  }

  var isInCall: Bool { bannerPhase != nil }

  func titleState(isOnline: Bool) -> TitleBubble.State {
    if isInCall { return .inCall }
    return isOnline ? .online : .offline
  }
}
