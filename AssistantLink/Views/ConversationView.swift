import SwiftUI

struct ConversationView: View {
  let assistantID: Assistant.ID

  @Environment(AppModel.self) private var model
  @State private var pairingLink: Link?
  @State private var failedMessage: OutgoingMessage?
  @State private var position = ScrollPosition()
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    if let assistant = model.assistant(id: assistantID) {
      Group {
        if assistant.links.isEmpty {
          SetupGuideView(assistant: assistant) { pairingLink = $0 }
        } else {
          timeline(assistant)
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        titleBubble(assistant)
        ToolbarItem(placement: .topBarTrailing) {
          Menu("More", systemImage: "ellipsis") {
            NavigationLink(value: Route.details(assistant.id)) {
              Label("Details", systemImage: "info.circle")
            }
          }
          .accessibilityIdentifier("moreButton")
        }
      }
      .overlay(alignment: .top) {
        CallGlow()
          .opacity(call(for: assistant).isInCall ? 1 : 0)
          .ignoresSafeArea()
      }
      .safeAreaInset(edge: .top) {
        if let phase = call(for: assistant).bannerPhase {
          CallBanner(
            phase: phase, avatar: Avatar(id: assistant.avatar),
            amplitude: model.voiceCall.amplitude,
            onMute: { model.voiceCall.setMuted(!model.voiceCall.isMuted) },
            onEnd: { model.endVoiceCall() }
          )
          .padding(.horizontal, 16)
          .padding(.vertical, 4)
          .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
      .animation(.easeInOut(duration: 0.3), value: call(for: assistant).isInCall)
      .onChange(of: scenePhase) {
        if scenePhase == .background { model.endVoiceCall() }
      }
      .onDisappear { if call(for: assistant).isInCall { model.endVoiceCall() } }
      .sheet(item: $pairingLink) { link in
        PairingView(
          assistantName: assistant.name, linkID: link.id,
          linkName: link.displayName(position: assistant.links.firstIndex(of: link) ?? 0))
      }
    } else {
      ContentUnavailableView("Assistant not found", systemImage: "questionmark.circle")
    }
  }

  /// The title bubble draws its own glass; the bar's would wrap it a second time on iOS 26.
  @ToolbarContentBuilder
  private func titleBubble(_ assistant: Assistant) -> some ToolbarContent {
    if #available(iOS 26.0, *) {
      ToolbarItem(placement: .principal) { titleLink(assistant) }
        .sharedBackgroundVisibility(.hidden)
    } else {
      ToolbarItem(placement: .principal) { titleLink(assistant) }
    }
  }

  private func titleLink(_ assistant: Assistant) -> some View {
    NavigationLink(value: Route.details(assistant.id)) {
      TitleBubble(
        name: assistant.name, avatar: Avatar(id: assistant.avatar),
        state: call(for: assistant).titleState(isOnline: assistant.status == .online))
    }
    .buttonStyle(.plain)
    .accessibilityHint("Shows the Assistant's details and Links")
  }

  private func call(for assistant: Assistant) -> CallPresentation {
    CallPresentation(model.voiceCall, assistantID: assistant.id)
  }

  private func timeline(_ assistant: Assistant) -> some View {
    let content = model.timelines[assistant.id] ?? Timeline()
    return ScrollView {
      LazyVStack(spacing: 12) {
        if content.hasMore {
          LoadEarlierButton(assistantID: assistant.id) { first in
            // Scrolling back to the old first event keeps the messages on screen in place.
            if let first { position.scrollTo(id: first, anchor: .top) }
          }
        }
        ForEach(Array(content.events.enumerated()), id: \.element.id) { index, event in
          VStack(spacing: 12) {
            if content.showsTimeCaption(beforeEventAt: index), event.type == .textMessage {
              TimeCaptionView(date: event.createdAt)
            }
            eventView(event, in: assistant, timeline: content)
          }
        }
        ForEach(Array(content.outgoing.enumerated()), id: \.element.id) { index, message in
          VStack(spacing: 12) {
            if content.showsTimeCaption(beforeOutgoingAt: index) {
              TimeCaptionView(date: message.createdAt)
            }
            MessageBubble(
              text: message.text, isFromUser: true,
              caption: content.caption(forMessageID: message.id), isVoice: message.via == .voice,
              onFailureTap: message.state == .failed ? { failedMessage = message } : nil)
          }
        }
      }
      .scrollTargetLayout()
      .padding(.horizontal, 16)
      .padding(.vertical, 24)
    }
    .defaultScrollAnchor(.bottom)
    .scrollPosition($position)
    .onChange(of: content.outgoing.last?.id) { position.scrollTo(edge: .bottom) }
    .onChange(of: content.events.last?.id) { position.scrollTo(edge: .bottom) }
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

private struct SetupGuideView: View {
  let assistant: Assistant
  let onCreate: (Link) -> Void

  @Environment(AppModel.self) private var model
  @State private var isSaving = false
  @State private var error: String?

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        VStack(spacing: 12) {
          AvatarView(avatar: Avatar(id: assistant.avatar), size: 72)
          Text("Connect \(assistant.name) to your agent")
            .font(.title2.bold())
          Text(
            "An Assistant Link connects \(assistant.name) to the agent that runs it, on your computer or in the cloud."
          )
          .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)

        VStack(alignment: .leading, spacing: 20) {
          step(
            1, "Get the pairing text",
            "It holds a code that pairs your agent with \(assistant.name).")
          step(2, "Paste it to your agent", "It explains everything the agent needs to do.")
          step(3, "Your agent connects", "\(assistant.name) shows as online while it is connected.")
        }

        if let error {
          Text(error).font(.footnote).foregroundStyle(.red)
        }

        Button(action: create) {
          if isSaving {
            ProgressView().frame(maxWidth: .infinity)
          } else {
            Text("Get Pairing Text").frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isSaving)
        .accessibilityIdentifier("createLink")
      }
      .padding(24)
    }
  }

  private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text("\(number)")
        .font(.subheadline.bold())
        .foregroundStyle(.white)
        .frame(width: 24, height: 24)
        .background(Circle().fill(.tint))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(detail).font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }

  private func create() {
    guard !isSaving else { return }
    isSaving = true
    error = nil
    Task {
      defer { isSaving = false }
      do {
        onCreate(try await model.createLink(assistantID: assistant.id))
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

#Preview("Conversation") {
  NavigationStack {
    ConversationView(assistantID: Assistant.samples[0].id)
  }
  .environment(AppModel.preview(Assistant.samples, timelines: Assistant.sampleTimelines))
}

#Preview("Setup guide") {
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
