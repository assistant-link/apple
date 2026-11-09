import SwiftUI

struct MessageBubble: View {
  let text: String
  let isFromUser: Bool
  var isDeleted = false
  var caption: MessageCaption?
  var isVoice = false
  var onFailureTap: (() -> Void)?

  var body: some View {
    VStack(alignment: isFromUser ? .trailing : .leading, spacing: 4) {
      HStack(spacing: 8) {
        if isFromUser { Spacer(minLength: 48) }
        if let onFailureTap {
          FailureBadge(action: onFailureTap)
        }
        ChatBubble(text: isDeleted ? "This message was deleted" : text, style: style)
          .frame(maxWidth: 295, alignment: isFromUser ? .trailing : .leading)
          .onTapGesture { onFailureTap?() }
        if !isFromUser { Spacer(minLength: 48) }
      }
      if let caption {
        DeliveryCaption(caption: caption, isVoice: isVoice)
      }
    }
    .frame(maxWidth: .infinity, alignment: isFromUser ? .trailing : .leading)
  }

  private var style: ChatBubble.Style {
    if isDeleted { return .deleted }
    return isFromUser ? .outgoing : .incoming
  }
}

struct LoadEarlierButton: View {
  let assistantID: Assistant.ID
  /// Called with the id of the row that was first before the page loaded.
  let onLoaded: (String?) -> Void

  @Environment(AppModel.self) private var model
  @State private var isLoading = false

  var body: some View {
    Button {
      guard !isLoading else { return }
      isLoading = true
      Task {
        defer { isLoading = false }
        let first = model.timelines[assistantID]?.rows.first?.id
        try? await model.loadEarlier(assistantID: assistantID)
        onLoaded(first)
      }
    } label: {
      if isLoading {
        ProgressView()
      } else {
        Text("Load Earlier Messages")
      }
    }
    .font(.subheadline)
    .frame(maxWidth: .infinity)
    .disabled(isLoading)
    .accessibilityIdentifier("loadEarlier")
  }
}

struct ComposerView: View {
  let assistant: Assistant

  @Environment(AppModel.self) private var model
  @State private var draft = ""

  /// The banner already says the call is waiting for the Assistant.
  private var isInCall: Bool {
    CallPresentation(model.voiceCall, assistantID: assistant.id).isInCall
  }

  var body: some View {
    VStack(spacing: 8) {
      if !isInCall, let notice = assistant.offlineNotice {
        Text(notice)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .accessibilityIdentifier("offlineNotice")
      }
      MessageComposer(draft: $draft, isInCall: isInCall, onSend: send)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  private func send() {
    let text = draft
    draft = ""
    Task { await model.send(text: text, assistantID: assistant.id) }
  }
}
