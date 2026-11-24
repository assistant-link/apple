import SwiftUI

/// The message field with its buttons. Starting a voice chat is not here: it is in the title bar.
/// It does not know about the conversation: the owner
/// supplies the draft and the actions.
struct MessageComposer: View {
  @Binding var draft: String
  var isInCall = false
  var focusRequest = 0
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
      MessageTextView(text: $draft, focusRequest: focusRequest)
        .overlay(alignment: .topLeading) {
          if draft.isEmpty {
            Text("Message")
              .foregroundStyle(Color(.placeholderText))
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .disabled(!state.isFieldEnabled)
        // Centres a single line on the 44 pt buttons, and the last line once it wraps.
        .padding(.vertical, 11)
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

/// Above the composer while the user replies to a message.
struct ReplyQuoteBar: View {
  let title: String
  let text: String
  let onCancel: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      RoundedRectangle(cornerRadius: 1.5)
        .fill(.tint)
        .frame(width: 3, height: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.footnote.weight(.semibold))
        Text(text)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: 0)
      Button("Cancel Reply", systemImage: "xmark", action: onCancel)
        .buttonStyle(.circle(foreground: .secondary, diameter: 28))
        .accessibilityIdentifier("cancelReplyButton")
    }
    .padding(.leading, 12)
    .padding(.trailing, 2)
    .padding(.vertical, 4)
    .glassBackground(in: RoundedRectangle(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20).strokeBorder(Color(.separator), lineWidth: 0.5)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("replyQuoteBar")
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
