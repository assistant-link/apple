import SwiftUI

struct MessageBubble: View {
  let text: String
  let isFromUser: Bool
  var isDeleted = false
  var caption: MessageCaption?
  var isVoice = false
  var onFailureTap: (() -> Void)?
  var quote: ReplyQuote?
  var onQuoteTap: (() -> Void)?
  /// Offers Reply and Copy; `nil` for a message that can't be replied to.
  var onReply: (() -> Void)?

  var body: some View {
    VStack(alignment: isFromUser ? .trailing : .leading, spacing: 4) {
      HStack(spacing: 8) {
        if isFromUser { Spacer(minLength: 48) }
        if let onFailureTap {
          FailureBadge(action: onFailureTap)
        }
        ChatBubble(
          text: isDeleted ? "This message was deleted" : text, style: style,
          quote: isDeleted ? nil : quote?.text,
          onQuoteTap: quote?.isTappable == true ? onQuoteTap : nil
        )
        .replyActions(text: text, onReply: onReply)
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

extension View {
  /// Swiping right or long-pressing to reply, with Copy in the menu, as in Messages.
  @ViewBuilder
  fileprivate func replyActions(text: String, onReply: (() -> Void)?) -> some View {
    if let onReply {
      modifier(ReplySwipe(onReply: onReply))
        .contextMenu {
          Button("Reply", systemImage: "arrow.turn.up.left", action: onReply)
          Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
        }
        .accessibilityAction(named: "Reply", onReply)
    } else {
      self
    }
  }
}

/// Dragging the bubble to the right uncovers a Reply disc; letting go past it starts the reply.
private struct ReplySwipe: ViewModifier {
  let onReply: () -> Void

  private static let threshold: CGFloat = 48

  @State private var offset: CGFloat = 0
  /// Decided by the first movement, so a vertical drag keeps scrolling the conversation.
  @State private var isSwiping: Bool?

  func body(content: Content) -> some View {
    content
      .offset(x: offset)
      .background(alignment: .leading) {
        Image(systemName: "arrow.turn.up.left")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: 32, height: 32)
          .background(Color(.tertiarySystemFill), in: Circle())
          .opacity(min(1, offset / Self.threshold))
          .accessibilityHidden(true)
      }
      .sensoryFeedback(.impact(weight: .light), trigger: offset >= Self.threshold) { _, isPast in
        isPast
      }
      .simultaneousGesture(
        DragGesture(minimumDistance: 16)
          .onChanged { value in
            let translation = value.translation
            if isSwiping == nil {
              isSwiping = translation.width > abs(translation.height)
            }
            guard isSwiping == true else { return }
            let width = max(0, translation.width)
            // Past the threshold the bubble follows the finger more slowly.
            offset = min(width, Self.threshold) + max(0, width - Self.threshold) / 4
          }
          .onEnded { _ in
            if offset >= Self.threshold { onReply() }
            isSwiping = nil
            withAnimation(.spring(duration: 0.3)) { offset = 0 }
          })
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
  /// Kept by the conversation, which starts replies from its messages.
  @Binding var draft: MessageDraft

  @Environment(AppModel.self) private var model
  @State private var focusRequest = 0
  @State private var dictationFailure: VoiceCall.StartFailure?

  private var dictation: Dictation { model.dictation }

  /// The call sheet already says the call is waiting for the Assistant.
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
      if let target = draft.replyTarget {
        ReplyQuoteBar(
          title: target.title(assistantName: assistant.name), text: target.text,
          onCancel: { draft.replyTarget = nil })
      }
      field
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .startFailureAlert("Can't dictate", failure: $dictationFailure)
    // A recording stopped by the user, or by the recognizer, leaves its words to fix.
    .onChange(of: dictation.phase) {
      if dictation.phase == .editing { draft.text = dictation.take() }
    }
    .onChange(of: draft.replyTarget?.eventID) { _, id in
      if id != nil { focusRequest += 1 }
    }
    // The call listens on its own, and a recording must not outlive the screen.
    .onChange(of: isInCall) { if isInCall { dictation.cancel() } }
    .onDisappear { dictation.cancel() }
  }

  @ViewBuilder
  private var field: some View {
    switch dictation.phase {
    case .preparing, .recording, .finishing:
      DictationComposer(
        phase: composerPhase,
        assistantName: assistant.name, confirmed: dictation.confirmed,
        provisional: dictation.provisional, levels: dictation.levels,
        onSend: { dictation.send { send($0, replyTo: draft.take().replyTo) } },
        onStop: { dictation.stop() })
    case .idle, .editing:
      MessageComposer(
        draft: $draft.text, isInCall: isInCall, focusRequest: focusRequest,
        onSend: {
          let taken = draft.take()
          send(taken.text, replyTo: taken.replyTo)
        },
        onDictate: startDictation)
    }
  }

  private var composerPhase: DictationComposer.Phase {
    switch dictation.phase {
    case .preparing: .preparing
    case .recording: .recording(seconds: dictation.seconds)
    case .finishing: .finishing
    case .idle: .idle
    case .editing: .editing
    }
  }

  private func startDictation() {
    Task {
      await dictation.start(after: draft.text, assistantName: assistant.name)
      dictationFailure = dictation.failure
    }
  }

  private func send(_ text: String, replyTo: String?) {
    Task { await model.send(text: text, assistantID: assistant.id, replyTo: replyTo) }
  }
}
