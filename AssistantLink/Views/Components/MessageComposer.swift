import SwiftUI

/// The message field with its buttons. Starting a voice chat is not here: it is in the title bar.
/// It does not know about the conversation: the owner
/// supplies the draft and the actions.
struct MessageComposer: View {
  @Binding var draft: String
  var isInCall = false
  let onSend: () -> Void
  var onDictate: () -> Void = {}

  private var state: ComposerState { ComposerState(draft: draft, isInCall: isInCall) }

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      // Reserved for attachments, which do not exist yet.
      Button("Attach", systemImage: "plus") {}
        .buttonStyle(.circle())
        .disabled(true)
        .accessibilityIdentifier("attachButton")
      TextField("Message", text: $draft, axis: .vertical)
        .lineLimit(1...DictationComposer.maxLines)
        .disabled(!state.isFieldEnabled)
        // Centres a single line on the 44 pt buttons, and the last line once it wraps.
        .padding(.vertical, 11)
        .accessibilityIdentifier("messageField")
      switch state.trailingButton {
      case .dictate:
        Button("Dictate", systemImage: "mic", action: onDictate)
          .buttonStyle(.circle())
          .accessibilityIdentifier("dictationButton")
      case .send:
        SendButton(action: onSend)
          .disabled(!state.canSend)
      case nil:
        EmptyView()
      }
    }
    .composerBox()
  }
}

/// The trailing button once there are words to send, in the spot of the dictation button.
struct SendButton: View {
  let action: () -> Void

  var body: some View {
    Button("Send", systemImage: "arrow.up", action: action)
      .buttonStyle(.circle(foreground: .white, background: .accentColor))
      .accessibilityIdentifier("sendButton")
  }
}

extension View {
  /// The box around the field and its buttons. Its corner radius stays the same at every height,
  /// where a capsule would grow into a blob, and the padding keeps the discs inside the corners.
  func composerBox() -> some View {
    padding(6)
      .glassBackground(in: RoundedRectangle(cornerRadius: 24))
      .overlay {
        RoundedRectangle(cornerRadius: 24).strokeBorder(Color(.separator), lineWidth: 0.5)
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("messageComposer")
  }
}
