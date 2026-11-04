import SwiftUI

/// The design-system components with sample data. The previews show it, and `-componentCatalog
/// <page>` opens one page as the app's only screen, which the screenshots job captures.
struct ComponentCatalog: View {
  enum Page: String, CaseIterable {
    case messages
    case composer
    case call
    case chat
    case callConnecting = "call-connecting"
    case callLive = "call-live"
    case afterCall = "after-call"
    case pairing

    /// Only in debug builds, so a release build cannot be steered to the sample screens.
    static var launched: Page? {
      #if DEBUG
        UserDefaults.standard.string(forKey: "componentCatalog").flatMap(Page.init)
      #else
        nil
      #endif
    }
  }

  let page: Page

  var body: some View {
    if page == .pairing {
      NavigationStack { ConversationView(assistantID: Assistant.samples[1].id) }
        .environment(AppModel.preview(Assistant.samples))
        .accessibilityIdentifier("componentCatalog")
    } else if let model = chatModel {
      NavigationStack { ConversationView(assistantID: Assistant.samples[0].id) }
        .environment(model)
        .task { await startCall(on: model) }
        .accessibilityIdentifier("componentCatalog")
    } else {
      pages
    }
  }

  /// The chat screen of the design mocks, in the state of the page.
  private var chatModel: AppModel? {
    var assistants = Assistant.samples
    switch page {
    case .chat, .afterCall: break
    case .callConnecting: assistants[0].status = .offline
    case .callLive: break
    default: return nil
    }
    let timeline = page == .afterCall ? Timeline.designMockAfterCall : .designMock
    return AppModel.preview(
      assistants, timelines: [assistants[0].id: timeline], voiceCall: .preview())
  }

  private func startCall(on model: AppModel) async {
    guard page == .callConnecting || page == .callLive else { return }
    _ = await model.startVoiceCall(assistantID: Assistant.samples[0].id)
  }

  private var pages: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(page.rawValue.capitalized)
        .font(.title2.bold())
        .accessibilityIdentifier("componentCatalog")
      switch page {
      case .messages: messages
      case .composer: composer
      case .call: call
      case .chat, .callConnecting, .callLive, .afterCall, .pairing: EmptyView()
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
      TitleBubble(name: "Hermes", avatar: Avatar(id: "avatar-3"), status: .online)
      TitleBubble(name: "Hermes", avatar: Avatar(id: "avatar-3"), status: .offline)
      TitleBubble(name: "Hermes", avatar: Avatar(id: "avatar-3"), status: .inCall)
      ForEach([CallBannerPhase.connecting, .live, .muted, .notListening], id: \.self) { phase in
        CallBanner(
          phase: phase, avatar: Avatar(id: "avatar-3"), onRetry: {}, onMute: {}, onEnd: {})
      }
    }
  }
}

#Preview("Messages") { ComponentCatalog(page: .messages) }
#Preview("Messages, dark") {
  ComponentCatalog(page: .messages).preferredColorScheme(.dark)
}
#Preview("Composer") { ComponentCatalog(page: .composer) }
#Preview("Composer, dark") {
  ComponentCatalog(page: .composer).preferredColorScheme(.dark)
}
#Preview("Call") { ComponentCatalog(page: .call) }
#Preview("Call, dark") {
  ComponentCatalog(page: .call).preferredColorScheme(.dark)
}

#Preview("Chat in a call, connecting") { ComponentCatalog(page: .callConnecting) }
#Preview("Chat in a call, live") { ComponentCatalog(page: .callLive) }
#Preview("Chat after a call") { ComponentCatalog(page: .afterCall) }
#Preview("Chat in a call, live, dark") {
  ComponentCatalog(page: .callLive).preferredColorScheme(.dark)
}

#Preview("Chat") { ComponentCatalog(page: .chat) }
#Preview("Chat, dark") { ComponentCatalog(page: .chat).preferredColorScheme(.dark) }
