import SwiftUI
import UIKit

/// The message field, a text view rather than a `TextField`: clearing a `TextField` leaves the
/// words keyboard dictation has not committed yet marked in place, so they come back after Send.
struct MessageTextView: UIViewRepresentable {
  @Binding var text: String
  /// Each change puts the cursor in the field and brings up the keyboard.
  var focusRequest = 0

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, focusRequest: focusRequest)
  }

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.delegate = context.coordinator
    textView.font = .preferredFont(forTextStyle: .body)
    textView.adjustsFontForContentSizeCategory = true
    textView.textColor = .label
    textView.backgroundColor = .clear
    textView.textContainerInset = .zero
    textView.textContainer.lineFragmentPadding = 0
    // Long words wrap instead of widening the composer.
    textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textView.accessibilityLabel = "Message"
    textView.accessibilityIdentifier = "messageField"
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.text = $text
    let isEnabled = context.environment.isEnabled
    textView.isEditable = isEnabled
    textView.isSelectable = isEnabled
    textView.textColor = isEnabled ? .label : .secondaryLabel
    if isEnabled {
      textView.accessibilityTraits.remove(.notEnabled)
    } else {
      textView.accessibilityTraits.insert(.notEnabled)
    }
    context.coordinator.show(text, in: textView)
    if context.coordinator.focusRequest != focusRequest {
      context.coordinator.focusRequest = focusRequest
      if isEnabled { textView.becomeFirstResponder() }
    }
  }

  /// The height of the text, up to as many lines as dictation shows; beyond that it scrolls.
  func sizeThatFits(
    _ proposal: ProposedViewSize, uiView textView: UITextView, context: Context
  ) -> CGSize? {
    guard let width = proposal.width else { return nil }
    let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    return CGSize(width: width, height: min(fitting.height, DictationComposer.maxHeight))
  }

  @MainActor final class Coordinator: NSObject, UITextViewDelegate {
    var text: Binding<String>
    var focusRequest: Int
    private var isShowing = false

    init(text: Binding<String>, focusRequest: Int = 0) {
      self.text = text
      self.focusRequest = focusRequest
    }

    /// Ends any dictation or composition before replacing the text: left marked, the keyboard
    /// commits the words later, on top of the new text.
    func show(_ newText: String, in textView: UITextView) {
      guard textView.text != newText else { return }
      isShowing = true
      defer { isShowing = false }
      let isComposing =
        textView.markedTextRange != nil || textView.textInputMode?.primaryLanguage == "dictation"
      textView.unmarkText()
      // Dictation keeps inserting what it hears until the field loses focus.
      if isComposing, textView.isFirstResponder {
        textView.resignFirstResponder()
        if textView.isEditable { textView.becomeFirstResponder() }
      }
      textView.text = newText
    }

    func textViewDidChange(_ textView: UITextView) {
      if !isShowing { text.wrappedValue = textView.text }
    }
  }
}
