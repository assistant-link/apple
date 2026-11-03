import Testing

@testable import AssistantLink

struct CallBannerPhaseTests {
  @Test func connectingWhileWaitingForTheAssistant() {
    #expect(CallBannerPhase(state: .connecting, isMuted: false) == .connecting)
  }

  @Test func liveWhileListeningOrSpeaking() {
    #expect(CallBannerPhase(state: .listening, isMuted: false) == .live)
    #expect(CallBannerPhase(state: .speaking, isMuted: false) == .live)
  }

  @Test func mutedWinsOverTheState() {
    #expect(CallBannerPhase(state: .listening, isMuted: true) == .muted)
    #expect(CallBannerPhase(state: .connecting, isMuted: true) == .muted)
  }
}
