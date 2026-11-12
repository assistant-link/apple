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
    #expect(none.offersStartCall)
    #expect(none.titleStatus(.online) == .online)
    #expect(none.titleStatus(.idle) == .idle)
    #expect(none.titleStatus(.offline) == .offline)
  }

  @Test func callWithAnotherAssistantDoesNotShowHere() {
    #expect(!presentation(.listening, callWith: "assistant-2").isInCall)
    #expect(presentation(.listening, callWith: "assistant-2").offersStartCall)
  }

  @Test func connectingCallShowsTheConnectingBannerAndTheCallTitle() {
    let connecting = presentation(.connecting)
    #expect(connecting.isInCall)
    #expect(connecting.bannerPhase == .connecting)
    #expect(!connecting.offersStartCall)
    #expect(connecting.titleStatus(.offline) == .inCall)
  }

  @Test func liveCallShowsTheLiveBanner() {
    #expect(presentation(.listening).bannerPhase == .live)
    #expect(!presentation(.listening).offersStartCall)
    #expect(presentation(.speaking).bannerPhase == .live)
    #expect(presentation(.listening).titleStatus(.online) == .inCall)
  }

  @Test func mutedCallShowsTheMutedBanner() {
    #expect(presentation(.listening, muted: true).bannerPhase == .muted)
  }

  @Test func callThatGaveUpListeningShowsTheNotListeningBanner() {
    #expect(presentation(.listening, failed: true).bannerPhase == .notListening)
  }
}
