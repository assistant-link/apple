import SwiftUI

struct ConversationView: View {
  let assistantID: Assistant.ID

  @Environment(AppModel.self) private var model
  @State private var pairingLink: SheetRequest<Link>?
  @State private var failedMessage: SheetRequest<OutgoingMessage>?
  @State private var position = ScrollPosition()
  @State private var callDetent = PresentationDetent.large
  @State private var voiceChat: SheetRequest<VoiceChatRecord>?
  @State private var startFailure: VoiceCall.StartFailure?
  @State private var visit = ConversationVisit()
  @State private var isVisible = false
  @Environment(\.scenePhase) private var scenePhase
  var readMarks = ReadMarks()
  /// Previews cannot fetch, so a visit placed in advance stands in for the one `open` places.
  var previewVisit: ConversationVisit?

  private var dividerRowID: String? { (previewVisit ?? visit).dividerRowID }

  var body: some View {
    if let assistant = model.assistant(id: assistantID) {
      let call = CallPresentation(model.voiceCall, assistantID: assistant.id)
      Group {
        if assistant.links.isEmpty {
          FirstPairingView(assistant: assistant) { pairingLink = request($0) }
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
      .modifier(sheets(assistant, duringCall: false))
      .callSheet(
        isPresented: call.isInCall, assistant: assistant, detent: $callDetent,
        sheets: sheets(assistant, duringCall: true)
      )
      .onChange(of: call.isInCall) {
        if call.isInCall { callDetent = .large }
        // A sheet the call sheet presented went away with it.
        pairingLink = nil
        failedMessage = nil
        voiceChat = nil
      }
      .startFailureAlert("Can't start the voice chat", failure: $startFailure)
    } else {
      ContentUnavailableView("Assistant not found", systemImage: "questionmark.circle")
    }
  }

  private func sheets(_ assistant: Assistant, duringCall: Bool) -> ConversationSheets {
    ConversationSheets(
      assistant: assistant, duringCall: duringCall, pairingLink: $pairingLink,
      failedMessage: $failedMessage, voiceChat: $voiceChat,
      onTryAgain: { message in Task { await model.retry(message) } },
      onDelete: { message in model.cancel(message) })
  }

  private func request<Item>(_ item: Item) -> SheetRequest<Item> {
    SheetRequest(
      item: item, duringCall: CallPresentation(model.voiceCall, assistantID: assistantID).isInCall)
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
        status: call.titleStatus(assistant.status))
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
              if row.id == dividerRowID {
                UnreadDivider()
                TimeCaptionView(date: event.createdAt)
              } else if row.showsTimeCaption {
                TimeCaptionView(date: event.createdAt)
              }
              eventView(event, in: assistant, timeline: content)
            case .outgoing(let message):
              if row.showsTimeCaption { TimeCaptionView(date: message.createdAt) }
              MessageBubble(
                text: message.text, isFromUser: true,
                caption: content.caption(forMessageID: message.id),
                isVoice: message.via == .voice,
                onFailureTap: message.state == .failed ? { failedMessage = request(message) } : nil)
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
    .onChange(of: [content.lastRowID, dividerRowID]) { old, new in
      switch TimelineScroll(lastRowID: (old[0], new[0]), dividerRowID: (old[1], new[1])) {
      case .keep: break
      case .bottom(let animated):
        withAnimation(animated ? .default : nil) { position.scrollTo(edge: .bottom) }
      case .divider(let rowID): position.scrollTo(id: rowID, anchor: .top)
      }
    }
    .safeAreaInset(edge: .bottom) {
      // The call sheet takes the composer's place.
      if CallPresentation(model.voiceCall, assistantID: assistant.id).isInCall {
        Color.clear.frame(height: CallSheet.compactHeight)
      } else if assistant.hasPairedLink {
        ComposerView(assistant: assistant)
      }
    }
    .task { await open(assistant.id) }
    .onAppear { isVisible = true }
    .onDisappear {
      isVisible = false
      leave(assistant.id)
    }
    .onChange(of: scenePhase) { old, new in
      guard isVisible else { return }
      if new == .background {
        leave(assistant.id)
      } else if old == .background {
        Task { await open(assistant.id) }
      }
    }
    .refreshable {
      try? await model.refresh()
      try? await model.openConversation(assistantID: assistant.id)
    }
  }

  /// Places the divider once the latest events have loaded. A failed fetch leaves it unplaced.
  private func open(_ id: Assistant.ID) async {
    visit.open()
    guard (try? await model.openConversation(assistantID: id)) != nil else { return }
    visit.place(
      in: model.timelines[id]?.events ?? [], lastReadID: readMarks.lastReadID(assistantID: id))
  }

  /// Leaving the screen or the app marks everything the conversation showed as read.
  private func leave(_ id: Assistant.ID) {
    if visit.leave() {
      readMarks.markRead(model.timelines[id]?.events ?? [], assistantID: id)
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
    case .callStarted, .unknown:
      EmptyView()
    case .callEnded:
      let chat = timeline.voiceChat(endedBy: event)
      Button {
        voiceChat = request(chat)
      } label: {
        VoiceChatCaption(seconds: chat.seconds)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(VoiceChat.accessibilityLabel(seconds: chat.seconds))
      .accessibilityHint("Shows the transcript")
      .accessibilityIdentifier("voiceChatEntry")
    case .linkCreated:
      if let position = assistant.links.firstIndex(where: { $0.id == event.linkID }) {
        let link = assistant.links[position]
        SystemEventView(event: event, link: link, linkName: link.displayName(position: position)) {
          pairingLink = request(link)
        }
      }
    }
  }
}

/// The sheets the conversation opens, on the presenter the request was for.
private struct ConversationSheets: ViewModifier {
  let assistant: Assistant
  let duringCall: Bool
  @Binding var pairingLink: SheetRequest<Link>?
  @Binding var failedMessage: SheetRequest<OutgoingMessage>?
  @Binding var voiceChat: SheetRequest<VoiceChatRecord>?
  let onTryAgain: (OutgoingMessage) -> Void
  let onDelete: (OutgoingMessage) -> Void

  func body(content: Content) -> some View {
    content
      .sheet(item: presented($voiceChat)) { VoiceTranscriptSheet(chat: $0) }
      .failedMessageSheet(
        item: presented($failedMessage), onTryAgain: onTryAgain, onDelete: onDelete
      )
      .sheet(item: presented($pairingLink)) { link in
        PairingView(
          assistantName: assistant.name, linkID: link.id,
          linkName: link.displayName(position: assistant.links.firstIndex(of: link) ?? 0))
      }
  }

  private func presented<Item>(_ request: Binding<SheetRequest<Item>?>) -> Binding<Item?> {
    Binding(
      get: { request.wrappedValue?.presented(duringCall: duringCall) },
      set: { if $0 == nil { request.wrappedValue = nil } })
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

#Preview("Unread") {
  let id = Assistant.samples[0].id
  let readMarks = ReadMarks(defaults: UserDefaults(suiteName: "UnreadPreview")!)
  let events = Timeline.designMock.events
  readMarks.markRead(Array(events.prefix(6)), assistantID: id)
  var visit = ConversationVisit()
  visit.open()
  visit.place(in: events, lastReadID: readMarks.lastReadID(assistantID: id))
  return NavigationStack {
    ConversationView(assistantID: id, readMarks: readMarks, previewVisit: visit)
  }
  .environment(AppModel.preview(Assistant.samples, timelines: [id: .designMock]))
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
