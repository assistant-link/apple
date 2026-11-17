import SwiftUI
import Testing
import UIKit

@testable import AssistantLink

@MainActor
struct MessageTextViewTests {
  @Observable fileprivate final class Draft {
    var text = ""
  }

  private let draft: Draft
  private let coordinator: MessageTextView.Coordinator
  private let textView = UITextView()
  private let window: UIWindow

  init() throws {
    let scene = try #require(
      UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
    window = UIWindow(windowScene: scene)
    let draft = Draft()
    self.draft = draft
    coordinator = MessageTextView.Coordinator(text: Bindable(draft).text)
    textView.delegate = coordinator
    window.addSubview(textView)
    window.makeKeyAndVisible()
    textView.becomeFirstResponder()
  }

  @Test func typingUpdatesTheDraft() {
    textView.insertText("Call David")
    #expect(draft.text == "Call David")
  }

  /// Keyboard dictation keeps its words marked until it commits them, which may be after Send.
  @Test func sendingWhileTextIsMarkedLeavesTheFieldEmpty() throws {
    textView.setMarkedText("Call David", selectedRange: NSRange(location: 10, length: 0))
    try #require(textView.markedTextRange != nil)

    draft.text = ""
    coordinator.show("", in: textView)
    textView.unmarkText()

    #expect(textView.text == "")
    #expect(textView.markedTextRange == nil)
    #expect(draft.text == "")
    #expect(textView.isFirstResponder)
  }

  @Test func showingTheSameTextKeepsTheMarkedText() throws {
    textView.setMarkedText("Call", selectedRange: NSRange(location: 4, length: 0))
    try #require(textView.markedTextRange != nil)

    coordinator.show("Call", in: textView)

    #expect(textView.markedTextRange != nil)
  }
}
