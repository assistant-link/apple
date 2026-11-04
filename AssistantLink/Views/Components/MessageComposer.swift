import SwiftUI

/// The message field with its buttons. It does not know about the conversation: the owner
/// supplies the draft and the actions.
struct MessageComposer: View {
  @Binding var draft: String
  var isInCall = false
  let onSend: () -> Void
  let onVoiceChat: () -> Void

  @FocusState private var isFocused: Bool

  private var state: ComposerState { ComposerState(draft: draft, isInCall: isInCall) }

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      // Reserved for attachments, which do not exist yet.
      Button("Attach", systemImage: "plus") {}
        .buttonStyle(.circle())
        .disabled(true)
        .accessibilityIdentifier("attachButton")
      TextField("Message", text: $draft, axis: .vertical)
        .lineLimit(1...5)
        .focused($isFocused)
        .disabled(!state.isFieldEnabled)
        // Without it the field takes any extra height it is offered and draws its text at the top.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 7)
        .accessibilityIdentifier("messageField")
      if state.showsDictation {
        // iOS cannot start keyboard dictation from code; the keyboard's own microphone does it.
        Button("Dictate", systemImage: "mic") { isFocused = true }
          .buttonStyle(.circle())
          .accessibilityIdentifier("dictationButton")
      }
      switch state.trailingButton {
      case .voiceChat:
        Button("Voice chat", systemImage: "waveform", action: onVoiceChat)
          .buttonStyle(.circle(foreground: .white, background: .red))
          .accessibilityIdentifier("voiceButton")
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
    .frame(minHeight: 48)
    .glassBackground(in: Capsule())
    .overlay { Capsule().strokeBorder(Color(.separator), lineWidth: 0.5) }
  }

  private var fill: Color { Color(.tertiarySystemFill) }
}
