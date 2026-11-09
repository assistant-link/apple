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
  /// Called with the id of the event that was first before the page loaded.
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
  @State private var dictation = Dictation.live()
  @State private var dictationFailure: VoiceCall.StartFailure?

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
      field
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .startFailureAlert("Can't dictate", failure: $dictationFailure)
    // A recording stopped by the user, or by the recognizer, leaves its words to fix.
    .onChange(of: dictation.phase) {
      if dictation.phase == .editing { draft = dictation.take() }
    }
    // The call listens on its own, and a recording must not outlive the screen.
    .onChange(of: isInCall) { if isInCall { dictation.cancel() } }
    .onDisappear { dictation.cancel() }
  }

  @ViewBuilder
  private var field: some View {
    switch dictation.phase {
    case .preparing, .recording:
      DictationComposer(
        phase: dictation.phase == .recording ? .recording(seconds: dictation.seconds) : .preparing,
        assistantName: assistant.name, confirmed: dictation.confirmed,
        provisional: dictation.provisional, levels: dictation.levels,
        onSend: { send(dictation.send()) }, onStop: { dictation.stop() })
    case .idle, .editing:
      MessageComposer(
        draft: $draft, isInCall: isInCall, onSend: { send(takeDraft()) }, onDictate: startDictation)
    }
  }

  private func startDictation() {
    Task {
      await dictation.start(after: draft, assistantName: assistant.name)
      dictationFailure = dictation.failure
    }
  }

  private func takeDraft() -> String {
    defer { draft = "" }
    return draft
  }

  private func send(_ text: String) {
    draft = ""
    Task { await model.send(text: text, assistantID: assistant.id) }
  }
}
