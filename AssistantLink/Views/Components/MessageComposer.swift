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
      circleButton("Attach", systemImage: "plus", foreground: .primary, background: fill) {}
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
        circleButton("Dictate", systemImage: "mic", foreground: .primary, background: fill) {
          isFocused = true
        }
        .accessibilityIdentifier("dictationButton")
      }
      switch state.trailingButton {
      case .voiceChat:
        circleButton(
          "Voice chat", systemImage: "waveform", foreground: .white, background: Color.red,
          action: onVoiceChat
        )
        .accessibilityIdentifier("voiceButton")
      case .send:
        circleButton(
          "Send", systemImage: "arrow.up", foreground: .white, background: Color.accentColor,
          action: onSend
        )
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

  private func circleButton<Background: ShapeStyle>(
    _ title: LocalizedStringKey, systemImage: String, foreground: Color, background: Background,
    action: @escaping () -> Void
  ) -> some View {
    Button(title, systemImage: systemImage, action: action)
      .labelStyle(.iconOnly)
      .font(.body.weight(.semibold))
      .buttonStyle(.plain)
      .foregroundStyle(foreground)
      .frame(width: 36, height: 36)
      .background(background, in: Circle())
  }
}
