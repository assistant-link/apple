import SwiftUI

/// The design-system components with sample data. The previews show it, and `-componentCatalog
/// <section>` opens one section as the app's only screen, which the screenshots job captures.
struct ComponentCatalog: View {
  enum Section: String, CaseIterable {
    case messages
    case composer
    case call
    case chat

    static var launched: Section? {
      UserDefaults.standard.string(forKey: "componentCatalog").flatMap(Section.init)
    }
  }

  let section: Section

  var body: some View {
    if section == .chat {
      NavigationStack { ConversationView(assistantID: Assistant.samples[0].id) }
        .environment(
          AppModel.preview(Assistant.samples, timelines: [Assistant.samples[0].id: .designMock])
        )
        .accessibilityIdentifier("componentCatalog")
    } else {
      sections
    }
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
      case .chat: EmptyView()
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
          phase: phase, avatar: Avatar(id: "avatar-3"), onMute: {}, onEnd: {}, onHide: {})
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

#Preview("Chat") { ComponentCatalog(section: .chat) }
#Preview("Chat, dark") { ComponentCatalog(section: .chat).preferredColorScheme(.dark) }
