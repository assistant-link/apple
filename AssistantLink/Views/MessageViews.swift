import SwiftUI

struct MessageBubble: View {
  let text: String
  let isFromUser: Bool
  var isDeleted = false
  var caption: MessageCaption?
  var onFailureTap: (() -> Void)?

  var body: some View {
    VStack(alignment: isFromUser ? .trailing : .leading, spacing: 4) {
      HStack(spacing: 8) {
        if isFromUser { Spacer(minLength: 48) }
        if let onFailureTap {
          Button(action: onFailureTap) {
            Image(systemName: "exclamationmark.circle.fill")
              .font(.title3)
              .foregroundStyle(.red)
          }
          .accessibilityLabel("Not Delivered")
          .accessibilityIdentifier("failedMessage")
        }
        Text(isDeleted ? "This message was deleted" : text)
          .italic(isDeleted)
          .foregroundStyle(foreground)
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
          .background(background, in: RoundedRectangle(cornerRadius: 18))
          .onTapGesture { onFailureTap?() }
        if !isFromUser { Spacer(minLength: 48) }
      }
      if let caption {
        Text(caption.text)
          .font(.caption)
          .foregroundStyle(caption == .notDelivered ? Color.red : Color.secondary)
          .padding(.horizontal, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: isFromUser ? .trailing : .leading)
  }

  private var foreground: Color {
    if isDeleted { return .secondary }
    return isFromUser ? .white : .primary
  }

  private var background: Color {
    if isDeleted { return Color(.secondarySystemFill) }
    return isFromUser ? .accentColor : Color(.secondarySystemBackground)
  }
}

struct LoadEarlierButton: View {
  let assistantID: Assistant.ID
  /// Called with the id of the event that is first before the page loads.
  let onLoaded: (String?) -> Void

  @Environment(AppModel.self) private var model
  @State private var isLoading = false

  var body: some View {
    Button {
      guard !isLoading else { return }
      isLoading = true
      Task {
        defer { isLoading = false }
        let first = model.timelines[assistantID]?.events.first?.id
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

  var body: some View {
    VStack(spacing: 8) {
      if let notice = assistant.offlineNotice {
        Text(notice)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .accessibilityIdentifier("offlineNotice")
      }
      HStack(alignment: .bottom, spacing: 8) {
        TextField("Message", text: $draft, axis: .vertical)
          .lineLimit(1...5)
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
          .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
          .accessibilityIdentifier("messageField")
        Button("Send", systemImage: "arrow.up.circle.fill", action: send)
          .labelStyle(.iconOnly)
          .font(.largeTitle)
          .disabled(!TextValidation.isValidMessage(draft))
          .accessibilityIdentifier("sendButton")
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.bar)
  }

  private func send() {
    let text = draft
    draft = ""
    Task { await model.send(text: text, assistantID: assistant.id) }
  }
}
