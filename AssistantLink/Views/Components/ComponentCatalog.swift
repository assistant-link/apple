import SwiftUI

/// The design-system components with sample data. The previews show it, and `-componentCatalog
/// <page>` opens one page as the app's only screen, which the screenshots job captures.
struct ComponentCatalog: View {
  enum Page: String, CaseIterable {
    case messages
    case composer
    case composerEmpty = "composer-empty"
    case composerOneLine = "composer-1-line"
    case composerThreeLines = "composer-3-lines"
    case composerEightLines = "composer-8-lines"
    case composerDictating = "composer-dictating"
    case call
    case chat
    case callConnecting = "call-connecting"
    case callLive = "call-live"
    case afterCall = "after-call"
    case pairing
    case dictationIdle = "dictation-idle"
    case dictationPreparing = "dictation-preparing"
    case dictationRecording = "dictation-recording"
    case dictationRecordingLong = "dictation-recording-long"
    case dictationEditing = "dictation-editing"

    static let dictation: [Page] = [
      .dictationIdle, .dictationPreparing, .dictationRecording, .dictationRecordingLong,
      .dictationEditing,
    ]

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
    } else if let lines = composerLines {
      inChat(MessageComposer(draft: .constant(Self.sampleLines(lines)), onSend: {}))
    } else if let composer = dictationComposer {
      inChat(composer)
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
      default: EmptyView()
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
      MessageComposer(draft: .constant(""), onSend: {})
      MessageComposer(
        draft: .constant("Also add it to my calendar"), onSend: {})
      MessageComposer(draft: .constant(""), isInCall: true, onSend: {})
      MessageComposer(draft: .constant(""), onSend: {})
        .disabled(true)
    }
  }

  /// The number of sample lines in the message field of the page, or nil on other pages.
  private var composerLines: Int? {
    switch page {
    case .composerEmpty: return 0
    case .composerOneLine: return 1
    case .composerThreeLines: return 3
    case .composerEightLines: return 8
    default: return nil
    }
  }

  /// Numbered lines, so a clipped last line is visible at a glance. Eight lines show the
  /// maximum height, with the field scrolling.
  static func sampleLines(_ count: Int) -> String {
    (0..<count).map { "Line \($0 + 1) of the message, with words to fill it" }
      .joined(separator: "\n")
  }

  /// The dictation design in the state of the page, or nil on other pages.
  private var dictationComposer: DictationComposer? {
    typealias Sample = DictationComposer
    let levels = Sample.sampleLevels
    switch page {
    case .dictationIdle: return DictationComposer(phase: .idle)
    case .dictationPreparing: return DictationComposer(phase: .preparing)
    case .dictationRecording:
      return DictationComposer(
        phase: .recording(seconds: 4), confirmed: Sample.sampleConfirmed,
        provisional: Sample.sampleProvisional,
        levels: levels)
    case .dictationRecordingLong:
      return DictationComposer(
        phase: .recording(seconds: 27), confirmed: Sample.sampleLongConfirmed,
        provisional: Sample.sampleLongProvisional,
        levels: levels)
    case .dictationEditing:
      return DictationComposer(
        phase: .editing, confirmed: Sample.sampleConfirmed + " at nine and add it to my calendar")
    case .composerDictating:
      return DictationComposer(
        phase: .recording(seconds: 12), confirmed: Self.sampleLines(3), provisional: "and then",
        levels: levels)
    default: return nil
    }
  }

  /// The composer at the bottom of a short sample chat, the way it would sit in a conversation.
  private func inChat(_ composer: some View) -> some View {
    VStack(spacing: 12) {
      Spacer(minLength: 0)
      ChatBubble(text: "What should I remind you about?", style: .incoming)
        .frame(maxWidth: .infinity, alignment: .leading)
      composer
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
    .accessibilityIdentifier("componentCatalog")
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
#Preview("Composer, empty") { ComponentCatalog(page: .composerEmpty) }
#Preview("Composer, 1 line") { ComponentCatalog(page: .composerOneLine) }
#Preview("Composer, 3 lines") { ComponentCatalog(page: .composerThreeLines) }
#Preview("Composer, 8 lines, scrolling") { ComponentCatalog(page: .composerEightLines) }
#Preview("Composer, 8 lines, dark") {
  ComponentCatalog(page: .composerEightLines).preferredColorScheme(.dark)
}
#Preview("Composer, dictating") { ComponentCatalog(page: .composerDictating) }
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

#Preview("Dictation, idle") { ComponentCatalog(page: .dictationIdle) }
#Preview("Dictation, preparing") { ComponentCatalog(page: .dictationPreparing) }
#Preview("Dictation, recording") { ComponentCatalog(page: .dictationRecording) }
#Preview("Dictation, recording six lines") { ComponentCatalog(page: .dictationRecordingLong) }
#Preview("Dictation, stopped to edit") { ComponentCatalog(page: .dictationEditing) }
#Preview("Dictation, recording, dark") {
  ComponentCatalog(page: .dictationRecording).preferredColorScheme(.dark)
}
