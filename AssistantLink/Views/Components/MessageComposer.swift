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
        .padding(.vertical, 7)
        .accessibilityIdentifier("messageField")
      if state.showsDictation {
        Button("Dictate", systemImage: "mic", action: onDictate)
          .buttonStyle(.circle())
          .accessibilityIdentifier("dictationButton")
      }
      switch state.trailingButton {
      case .send:
        Button("Send", systemImage: "arrow.up", action: onSend)
          .buttonStyle(.circle(foreground: .white, background: .accentColor))
          .disabled(!state.canSend)
          .accessibilityIdentifier("sendButton")
      case nil:
        EmptyView()
      }
    }
    .padding(6)
    // A capsule gets a radius of half its height, which squeezes and clips the text once the
    // field is several lines tall.
    .glassBackground(in: RoundedRectangle(cornerRadius: 24))
    .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color(.separator), lineWidth: 0.5) }
  }
}
