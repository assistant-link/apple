/// What a conversation screen shows of the voice chat: only a call with its own Assistant counts.
struct CallPresentation: Equatable {
  /// `nil` when there is no call with this Assistant.
  let bannerPhase: CallBannerPhase?

  init(
    state: VoiceCall.State, isMuted: Bool, listeningFailed: Bool, callAssistantID: Assistant.ID?,
    assistantID: Assistant.ID
  ) {
    if state == .idle || callAssistantID != assistantID {
      bannerPhase = nil
    } else {
      bannerPhase = CallBannerPhase(
        state: state, isMuted: isMuted, listeningFailed: listeningFailed)
    }
  }

  @MainActor
  init(_ call: VoiceCall, assistantID: Assistant.ID) {
    self.init(
      state: call.state, isMuted: call.isMuted, listeningFailed: call.listeningFailed,
      callAssistantID: call.assistantID, assistantID: assistantID)
  }

  var isInCall: Bool { bannerPhase != nil }

  /// The call sheet has End once the call is on, so the start control only shows before.
  var offersStartCall: Bool { !isInCall }

  func titleStatus(_ status: Assistant.Status) -> TitleBubble.Status {
    if isInCall { return .inCall }
    switch status {
    case .online: return .online
    case .idle: return .idle
    case .offline: return .offline
    }
  }
}

/// A sheet the conversation asked for. SwiftUI presents one sheet per presenter, so while the call
/// sheet is up it presents the sheets asked for behind its compact bar, and the conversation the
/// others. A request is for one presenter only, so it never shows late on the other.
struct SheetRequest<Item> {
  let item: Item
  let duringCall: Bool

  func presented(duringCall presenterDuringCall: Bool) -> Item? {
    duringCall == presenterDuringCall ? item : nil
  }
}
