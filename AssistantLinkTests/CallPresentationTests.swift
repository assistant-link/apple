import Testing

@testable import AssistantLink

struct CallPresentationTests {
  private let hermes = "assistant-1"

  private func presentation(
    _ state: VoiceCall.State, muted: Bool = false, failed: Bool = false,
    callWith: String? = "assistant-1"
  ) -> CallPresentation {
    CallPresentation(
      state: state, isMuted: muted, listeningFailed: failed, callAssistantID: callWith,
      assistantID: hermes)
  }

  @Test func noCallWhenIdle() {
    let none = presentation(.idle, callWith: nil)
    #expect(!none.isInCall)
    #expect(none.bannerPhase == nil)
    #expect(none.titleStatus(isOnline: true) == .online)
    #expect(none.titleStatus(isOnline: false) == .offline)
  }

  @Test func callWithAnotherAssistantDoesNotShowHere() {
    #expect(!presentation(.listening, callWith: "assistant-2").isInCall)
  }

  @Test func connectingCallShowsTheConnectingBannerAndTheCallTitle() {
    let connecting = presentation(.connecting)
    #expect(connecting.isInCall)
    #expect(connecting.bannerPhase == .connecting)
    #expect(connecting.titleStatus(isOnline: false) == .inCall)
  }

  @Test func liveCallShowsTheLiveBanner() {
    #expect(presentation(.listening).bannerPhase == .live)
    #expect(presentation(.speaking).bannerPhase == .live)
    #expect(presentation(.listening).titleStatus(isOnline: true) == .inCall)
  }

  @Test func mutedCallShowsTheMutedBanner() {
    #expect(presentation(.listening, muted: true).bannerPhase == .muted)
  }

  @Test func callThatGaveUpListeningShowsTheNotListeningBanner() {
    #expect(presentation(.listening, failed: true).bannerPhase == .notListening)
  }
}
