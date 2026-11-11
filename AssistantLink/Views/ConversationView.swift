import SwiftUI

struct ConversationView: View {
  let assistantID: Assistant.ID

  @Environment(AppModel.self) private var model
  @State private var pairingLink: Link?
  @State private var failedMessage: OutgoingMessage?
  @State private var position = ScrollPosition()
  @State private var isBannerHidden = false
  @State private var startFailure: VoiceCall.StartFailure?
  var body: some View {
    if let assistant = model.assistant(id: assistantID) {
      let call = CallPresentation(model.voiceCall, assistantID: assistant.id)
      Group {
        if assistant.links.isEmpty {
          FirstPairingView(assistant: assistant) { pairingLink = $0 }
        } else {
          timeline(assistant)
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        titleBubble(assistant, call)
        if call.offersStartCall, assistant.hasPairedLink {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Call", systemImage: "phone") { startCall(assistant) }
              .accessibilityIdentifier("voiceButton")
          }
        }
      }
      .overlay(alignment: .top) {
        CallGlow()
          .opacity(call.isInCall ? 1 : 0)
          .ignoresSafeArea()
      }
      .safeAreaInset(edge: .top) {
        if let phase = call.bannerPhase {
          Group {
            if isBannerHidden {
              Button("Show voice chat controls", systemImage: "chevron.down") {
                isBannerHidden = false
              }
              .buttonStyle(.circle(diameter: 28))
              .accessibilityIdentifier("showCallBanner")
            } else {
              VStack(spacing: 2) {
                CallBanner(
                  phase: phase, avatar: Avatar(id: assistant.avatar),
                  amplitude: { model.voiceCall.amplitude },
                  onRetry: { model.voiceCall.retryListening() },
                  onMute: { model.voiceCall.setMuted(!model.voiceCall.isMuted) },
                  onEnd: { model.endVoiceCall() }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                // Without it only the glyphs take the drag, not the gaps between the waveform bars.
                .contentShape(Rectangle())
                .gesture(
                  DragGesture(minimumDistance: 20).onEnded { drag in
                    if drag.translation.height < -20 { isBannerHidden = true }
                  }
                )
                .accessibilityAction(named: "Hide") { isBannerHidden = true }
                // Apart from the banner so that it never takes a Mute or End tap.
                Button("Hide voice chat controls", systemImage: "chevron.up") {
                  isBannerHidden = true
                }
                .buttonStyle(.circle(diameter: 28))
                .accessibilityIdentifier("hideCallBanner")
              }
            }
          }
          .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
      .animation(.easeInOut(duration: 0.3), value: isBannerHidden)
      .onChange(of: call.isInCall) { isBannerHidden = false }
      // The retry button lives in the banner, so a stalled call must bring it back.
      .onChange(of: call.bannerPhase) {
        if call.bannerPhase == .notListening { isBannerHidden = false }
      }
      .animation(.easeInOut(duration: 0.3), value: call.isInCall)
      .startFailureAlert("Can't start the voice chat", failure: $startFailure)
      .sheet(item: $pairingLink) { link in
        PairingView(
          assistantName: assistant.name, linkID: link.id,
          linkName: link.displayName(position: assistant.links.firstIndex(of: link) ?? 0))
      }
    } else {
      ContentUnavailableView("Assistant not found", systemImage: "questionmark.circle")
    }
  }

  private func startCall(_ assistant: Assistant) {
    Task {
      if await !model.startVoiceCall(assistantID: assistant.id) {
        startFailure = model.voiceCall.startFailure
      }
    }
  }

  /// The title bubble draws its own glass; the bar's would wrap it a second time on iOS 26.
  @ToolbarContentBuilder
  private func titleBubble(
    _ assistant: Assistant, _ call: CallPresentation
  ) -> some ToolbarContent {
    if #available(iOS 26.0, *) {
      ToolbarItem(placement: .principal) { titleLink(assistant, call) }
        .sharedBackgroundVisibility(.hidden)
    } else {
      ToolbarItem(placement: .principal) { titleLink(assistant, call) }
    }
  }

  private func titleLink(_ assistant: Assistant, _ call: CallPresentation) -> some View {
    NavigationLink(value: Route.details(assistant.id)) {
      TitleBubble(
        name: assistant.name, avatar: Avatar(id: assistant.avatar),
        status: call.titleStatus(isOnline: assistant.status == .online))
    }
    .buttonStyle(.plain)
    .accessibilityHint("Shows the Assistant's details and Links")
  }

  private func timeline(_ assistant: Assistant) -> some View {
    let content = model.timelines[assistant.id] ?? Timeline()
    return ScrollView {
      // Not lazy: when the composer or keyboard resizes the view, a lazy stack anchored to the
      // bottom can lose its place and draw nothing until the next scroll. Events load 50 to a
      // page, so laying out every message is cheap.
      VStack(spacing: 12) {
        if content.hasMore {
          LoadEarlierButton(assistantID: assistant.id) { first in
            // Scrolling back to the old first event keeps the messages on screen in place.
            if let first { position.scrollTo(id: first, anchor: .top) }
          }
        }
        ForEach(content.rows) { row in
          VStack(spacing: 12) {
            switch row.content {
            case .event(let event):
              if row.showsTimeCaption { TimeCaptionView(date: event.createdAt) }
              eventView(event, in: assistant, timeline: content)
            case .outgoing(let message):
              if row.showsTimeCaption { TimeCaptionView(date: message.createdAt) }
              MessageBubble(
                text: message.text, isFromUser: true,
                caption: content.caption(forMessageID: message.id),
                isVoice: message.via == .voice,
                onFailureTap: message.state == .failed ? { failedMessage = message } : nil)
            }
          }
        }
      }
      .scrollTargetLayout()
      .padding(.horizontal, 16)
      .padding(.vertical, 24)
    }
    .defaultScrollAnchor(.bottom)
    .scrollPosition($position)
    .onChange(of: content.lastRowID) { previous, _ in
      // The first load lands at the bottom without a visible scroll.
      withAnimation(previous == nil ? nil : .default) { position.scrollTo(edge: .bottom) }
    }
    .safeAreaInset(edge: .bottom) {
      if assistant.hasPairedLink {
        ComposerView(assistant: assistant)
      }
    }
    .failedMessageSheet(
      item: $failedMessage,
      onTryAgain: { message in Task { await model.retry(message) } },
      onDelete: { message in model.cancel(message) }
    )
    .task { try? await model.openConversation(assistantID: assistant.id) }
    .refreshable {
      try? await model.refresh()
      try? await model.openConversation(assistantID: assistant.id)
    }
  }

  @ViewBuilder
  private func eventView(_ event: Event, in assistant: Assistant, timeline: Timeline)
    -> some View
  {
    switch event.type {
    case .textMessage:
      MessageBubble(
        text: event.text ?? "", isFromUser: event.sender == .user, isDeleted: event.deleted,
        caption: timeline.caption(forMessageID: event.id), isVoice: event.via == .voice)
    case .callStarted:
      EmptyView()
    case .callEnded:
      VoiceChatCaption(seconds: timeline.voiceChatSeconds(endedBy: event))
    case .linkCreated:
      if let position = assistant.links.firstIndex(where: { $0.id == event.linkID }) {
        let link = assistant.links[position]
        SystemEventView(event: event, link: link, linkName: link.displayName(position: position)) {
          pairingLink = link
        }
      }
    }
  }
}

private struct SystemEventView: View {
  let event: Event
  let link: Link
  let linkName: String
  let showPairingText: () -> Void

  var body: some View {
    VStack(spacing: 6) {
      SystemEventCaption(
        date: event.createdAt,
        linkName: link.status == .notPaired ? "\(linkName) · not paired yet" : linkName)
      if link.status == .notPaired {
        Button("Show pairing text", action: showPairingText)
          .font(.subheadline)
      }
    }
    .frame(maxWidth: .infinity)
    .multilineTextAlignment(.center)
  }
}

#Preview("Conversation") {
  NavigationStack {
    ConversationView(assistantID: Assistant.samples[0].id)
  }
  .environment(AppModel.preview(Assistant.samples, timelines: Assistant.sampleTimelines))
}

#Preview("First pairing") {
  NavigationStack {
    ConversationView(assistantID: Assistant.samples[1].id)
  }
  .environment(AppModel.preview(Assistant.samples))
}

#Preview("Load earlier and deleted") {
  var events = Event.samples
  events[2].deleted = true
  events[2].text = nil
  let id = Assistant.samples[0].id
  return NavigationStack {
    ConversationView(assistantID: id)
  }
  .environment(
    AppModel.preview(
      Assistant.samples, timelines: [id: Timeline(events: events, hasMore: true)]))
}

#Preview("Not delivered") {
  let id = Assistant.samples[0].id
  let message = OutgoingMessage(
    assistantID: id, idempotencyKey: "01a11a4e-0a6b-7000-8000-0000000000b1",
    text: "Are you there?", createdAt: .now, state: .failed)
  return NavigationStack {
    ConversationView(assistantID: id)
  }
  .environment(
    AppModel.preview(
      Assistant.samples, timelines: [id: Timeline(events: Event.samples, outgoing: [message])]))
}

#Preview("Offline") {
  var assistants = Assistant.samples
  assistants[0].status = .offline
  return NavigationStack {
    ConversationView(assistantID: assistants[0].id)
  }
  .environment(AppModel.preview(assistants, timelines: Assistant.sampleTimelines))
}

#Preview("No paired Link") {
  NavigationStack {
    ConversationView(assistantID: Assistant.samples[2].id)
  }
  .environment(AppModel.preview(Assistant.samples))
}

extension View {
  /// Says why the microphone could not start; for a denied permission it offers the Settings.
  func startFailureAlert(_ title: String, failure: Binding<VoiceCall.StartFailure?>) -> some View {
    modifier(StartFailureAlert(title: title, failure: failure))
  }
}

private struct StartFailureAlert: ViewModifier {
  let title: String
  @Binding var failure: VoiceCall.StartFailure?
  @Environment(\.openURL) private var openURL

  func body(content: Content) -> some View {
    content.alert(
      title, isPresented: Binding(get: { failure != nil }, set: { _ in failure = nil }),
      presenting: failure
    ) { failure in
      if failure == .permissionDenied {
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
        Button("Cancel", role: .cancel) {}
      } else {
        Button("OK", role: .cancel) {}
      }
    } message: { failure in
      Text(
        failure == .permissionDenied
          ? "Allow Microphone and Speech Recognition for Assistant Link in Settings."
          : "The microphone or speech recognition could not start. Try again.")
    }
  }
}
