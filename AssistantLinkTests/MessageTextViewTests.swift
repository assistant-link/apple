import SwiftUI
import Testing
import UIKit

@testable import AssistantLink

/// Serialized: each test makes its window key and its text view first responder.
@MainActor @Suite(.serialized)
struct MessageTextViewTests {
  private final class Draft {
    var text = ""
  }

  private let draft: Draft
  private let coordinator: MessageTextView.Coordinator
  private let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
  private let window: UIWindow

  init() throws {
    let scene = try #require(
      UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
    window = UIWindow(windowScene: scene)
    let draft = Draft()
    self.draft = draft
    coordinator = MessageTextView.Coordinator(
      text: Binding(get: { draft.text }, set: { draft.text = $0 }))
    textView.delegate = coordinator
    let host = UIViewController()
    textView.frame = CGRect(x: 0, y: 100, width: 320, height: 44)
    host.view.addSubview(textView)
    window.rootViewController = host
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
