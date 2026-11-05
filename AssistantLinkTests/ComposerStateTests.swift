import Testing

@testable import AssistantLink

struct ComposerStateTests {
  @Test func emptyDraftOffersDictationAndNoTrailingButton() {
    let state = ComposerState(draft: "")
    #expect(state.trailingButton == nil)
    #expect(state.showsDictation)
    #expect(state.isFieldEnabled)
  }

  @Test func typingOffersSend() {
    let state = ComposerState(draft: "Also add it to my calendar")
    #expect(state.trailingButton == .send)
    #expect(state.showsDictation)
    #expect(state.canSend)
  }

  @Test func whitespaceCannotBeSent() {
    let state = ComposerState(draft: "  \n ")
    #expect(state.trailingButton == .send)
    #expect(!state.canSend)
  }

  @Test func callHidesDictationAndTheTrailingButtonAndLocksTheField() {
    for draft in ["", "Hello"] {
      let state = ComposerState(draft: draft, isInCall: true)
      #expect(state.trailingButton == nil)
      #expect(!state.showsDictation)
      #expect(!state.isFieldEnabled)
    }
  }
}
