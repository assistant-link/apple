import Testing

@testable import AssistantLink

struct ReplyVoiceNoticeTests {
  @Test func nothingShowsWhenKokoroIsNotUsed() {
    #expect(ReplyVoiceNotice(nil, confirmsReady: false) == nil)
    #expect(ReplyVoiceNotice(nil, confirmsReady: true) == nil)
  }

  @Test func theDownloadShowsItsPercentage() {
    let notice = ReplyVoiceNotice(.downloading(fraction: 0.424), confirmsReady: false)
    #expect(notice == .downloading(percent: 42))
    #expect(notice?.text == "Downloading Kokoro voice… 42%")
    #expect(notice?.isUnderway == true)
  }

  @Test func aDownloadWithoutProgressYetShowsNoNumber() {
    let notice = ReplyVoiceNotice(.downloading(fraction: nil), confirmsReady: false)
    #expect(notice == .downloading(percent: nil))
    #expect(notice?.text == "Downloading Kokoro voice…")
  }

  @Test func loadingTheModelShowsAsPreparing() {
    #expect(ReplyVoiceNotice(.preparing, confirmsReady: false) == .preparing)
    #expect(ReplyVoiceNotice(.notStarted, confirmsReady: false) == .preparing)
    #expect(ReplyVoiceNotice(.preparing, confirmsReady: false)?.text == "Preparing Kokoro voice…")
  }

  @Test func aFailureOffersARetry() {
    let notice = ReplyVoiceNotice(.failed, confirmsReady: false)
    #expect(notice == .failed)
    #expect(notice?.offersRetry == true)
    #expect(notice?.isUnderway == false)
  }

  @Test func readyShowsOnlyAsAShortConfirmation() {
    #expect(ReplyVoiceNotice(.ready, confirmsReady: false) == nil)
    #expect(ReplyVoiceNotice(.ready, confirmsReady: true) == .ready)
    #expect(ReplyVoiceNotice(.ready, confirmsReady: true)?.text == "Kokoro voice ready")
  }

  @Test func theConfirmationIsOnlyForReady() {
    #expect(ReplyVoiceNotice(.preparing, confirmsReady: true) == .preparing)
  }
}
