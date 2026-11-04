import Testing

@testable import AssistantLink

struct CallBannerPhaseTests {
  @Test func connectingWhileWaitingForTheAssistant() {
    #expect(
      CallBannerPhase(state: .connecting, isMuted: false, listeningFailed: false) == .connecting)
  }

  @Test func liveWhileListeningOrSpeaking() {
    #expect(CallBannerPhase(state: .listening, isMuted: false, listeningFailed: false) == .live)
    #expect(CallBannerPhase(state: .speaking, isMuted: false, listeningFailed: false) == .live)
  }

  @Test func mutedWinsOverTheState() {
    #expect(CallBannerPhase(state: .listening, isMuted: true, listeningFailed: false) == .muted)
    #expect(CallBannerPhase(state: .connecting, isMuted: true, listeningFailed: false) == .muted)
  }

  @Test func notListeningWhenListeningGaveUp() {
    #expect(
      CallBannerPhase(state: .listening, isMuted: false, listeningFailed: true) == .notListening)
    #expect(
      CallBannerPhase(state: .connecting, isMuted: false, listeningFailed: true) == .notListening)
  }

  @Test func mutedAndSpeakingWinOverGivingUp() {
    #expect(CallBannerPhase(state: .listening, isMuted: true, listeningFailed: true) == .muted)
    #expect(CallBannerPhase(state: .speaking, isMuted: false, listeningFailed: true) == .live)
  }
}
