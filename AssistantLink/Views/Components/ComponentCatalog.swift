import SwiftUI

/// The design-system components with sample data. The previews show it, and `-componentCatalog
/// <section>` opens one section as the app's only screen, which the screenshots job captures.
struct ComponentCatalog: View {
  enum Section: String, CaseIterable {
    case messages
    case composer
    case call
    case chat
    case callConnecting = "call-connecting"
    case callLive = "call-live"
    case afterCall = "after-call"

    static var launched: Section? {
      UserDefaults.standard.string(forKey: "componentCatalog").flatMap(Section.init)
    }
  }

  let section: Section

  var body: some View {
    if let model = chatModel {
      NavigationStack { ConversationView(assistantID: Assistant.samples[0].id) }
        .environment(model)
        .task { await startCall(on: model) }
        .accessibilityIdentifier("componentCatalog")
    } else {
      sections
    }
  }

  /// The chat screen of the design mocks, in the state of the section.
  private var chatModel: AppModel? {
    var assistants = Assistant.samples
    switch section {
    case .chat, .afterCall: break
    case .callConnecting: assistants[0].status = .offline
    case .callLive: break
    default: return nil
    }
    let timeline = section == .afterCall ? Timeline.designMockAfterCall : .designMock
    return AppModel.preview(
      assistants, timelines: [assistants[0].id: timeline], voiceCall: .preview())
  }

  private func startCall(on model: AppModel) async {
    guard section == .callConnecting || section == .callLive else { return }
    _ = await model.startVoiceCall(assistantID: Assistant.samples[0].id)
  }

  private var sections: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(section.rawValue.capitalized)
        .font(.title2.bold())
        .accessibilityIdentifier("componentCatalog")
      switch section {
      case .messages: messages
      case .composer: composer
      case .call: call
      case .chat, .callConnecting, .callLive, .afterCall: EmptyView()
      }
      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color(.systemBackground))
  }

  private var messages: some View {
    VStack(spacing: 12) {
      SystemEventCaption(date: .now.addingTimeInterval(-86_400), linkName: "Link 1")
      ChatBubble(text: "Done. I will remind you at 9:00.", style: .incoming)
        .frame(maxWidth: .infinity, alignment: .leading)
      ChatBubble(text: "Done. I will remind you at 9:00.", style: .outgoing)
        .frame(maxWidth: .infinity, alignment: .trailing)
      HStack(spacing: 8) {
        Spacer()
        FailureBadge {}
        ChatBubble(text: "Done. I will remind you at 9:00.", style: .outgoing)
      }
      ChatBubble(text: "This message was deleted", style: .deleted)
        .frame(maxWidth: .infinity, alignment: .trailing)
      VStack(alignment: .trailing, spacing: 4) {
        DeliveryCaption(caption: .sending)
        DeliveryCaption(caption: .sent)
        DeliveryCaption(caption: .delivered)
        DeliveryCaption(caption: .notDelivered)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
      TimeCaptionView(date: .now)
      VoiceChatCaption(seconds: 15)
    }
  }

  private var composer: some View {
    VStack(spacing: 16) {
      MessageComposer(draft: .constant(""), onSend: {}, onVoiceChat: {})
      MessageComposer(
        draft: .constant("Also add it to my calendar"), onSend: {}, onVoiceChat: {})
      MessageComposer(draft: .constant(""), isInCall: true, onSend: {}, onVoiceChat: {})
      MessageComposer(draft: .constant(""), onSend: {}, onVoiceChat: {})
        .disabled(true)
    }
  }

  private var call: some View {
    VStack(alignment: .leading, spacing: 16) {
      TitleBubble(name: "Hermes", avatar: Avatar(id: "avatar-3"), state: .online)
      TitleBubble(name: "Hermes", avatar: Avatar(id: "avatar-3"), state: .offline)
      TitleBubble(name: "Hermes", avatar: Avatar(id: "avatar-3"), state: .inCall)
      ForEach([CallBannerPhase.connecting, .live, .muted], id: \.self) { phase in
        CallBanner(
          phase: phase, avatar: Avatar(id: "avatar-3"), onMute: {}, onEnd: {})
      }
    }
  }
}

#Preview("Messages") { ComponentCatalog(section: .messages) }
#Preview("Messages, dark") {
  ComponentCatalog(section: .messages).preferredColorScheme(.dark)
}
#Preview("Composer") { ComponentCatalog(section: .composer) }
#Preview("Composer, dark") {
  ComponentCatalog(section: .composer).preferredColorScheme(.dark)
}
#Preview("Call") { ComponentCatalog(section: .call) }
#Preview("Call, dark") {
  ComponentCatalog(section: .call).preferredColorScheme(.dark)
}

#Preview("Chat in a call, connecting") { ComponentCatalog(section: .callConnecting) }
#Preview("Chat in a call, live") { ComponentCatalog(section: .callLive) }
#Preview("Chat after a call") { ComponentCatalog(section: .afterCall) }
#Preview("Chat in a call, live, dark") {
  ComponentCatalog(section: .callLive).preferredColorScheme(.dark)
}

#Preview("Chat") { ComponentCatalog(section: .chat) }
#Preview("Chat, dark") { ComponentCatalog(section: .chat).preferredColorScheme(.dark) }
