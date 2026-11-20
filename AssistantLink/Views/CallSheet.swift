import SwiftUI

/// The live voice chat: a sheet with the transcript and the call controls, which pulls down to a
/// compact bar while the call goes on. Only End hangs up.
struct CallSheet: View {
  static let compactHeight: CGFloat = 112
  static let compact = PresentationDetent.height(compactHeight)

  let assistant: Assistant
  @Binding var detent: PresentationDetent

  @Environment(AppModel.self) private var model

  var body: some View {
    let call = model.voiceCall
    CallSheetContent(
      name: assistant.name, avatar: Avatar(id: assistant.avatar),
      startedAt: call.startedAt ?? .now, lines: call.transcript,
      presentation: CallSheetPresentation(call), isSpeakerOn: call.isSpeakerOn,
      isCompact: detent == Self.compact, replyVoice: model.kokoro?.status,
      activity: assistant.activity,
      amplitude: { model.voiceCall.amplitude },
      actions: CallSheetContent.Actions(
        mute: { call.setMuted(!call.isMuted) },
        speaker: { call.setSpeaker(!call.isSpeakerOn) },
        end: { model.endVoiceCall() },
        retry: { call.retryListening() },
        retryReplyVoice: { model.retryReplyVoice() },
        expand: { detent = .large })
    )
  }
}

extension View {
  /// `sheets` presents the sheets the chat behind the compact bar opens, which the view under
  /// the call sheet can't while it is up.
  func callSheet(
    isPresented: Bool, assistant: Assistant, detent: Binding<PresentationDetent>,
    sheets: some ViewModifier
  ) -> some View {
    // Pulling the sheet down only collapses it, so nothing but the call ending dismisses it.
    sheet(isPresented: .constant(isPresented)) {
      CallSheet(assistant: assistant, detent: detent)
        .modifier(sheets)
        .presentationDetents([CallSheet.compact, .large], selection: detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackgroundInteraction(.enabled(upThrough: CallSheet.compact))
        .interactiveDismissDisabled()
    }
  }
}

/// The call sheet drawn from plain values, so the previews can show every state.
struct CallSheetContent: View {
  struct Actions {
    var mute: () -> Void = {}
    var speaker: () -> Void = {}
    var end: () -> Void = {}
    var retry: () -> Void = {}
    var retryReplyVoice: () -> Void = {}
    var expand: () -> Void = {}
  }

  let name: String
  let avatar: Avatar
  let startedAt: Date
  let lines: [TranscriptLine]
  let presentation: CallSheetPresentation
  var isSpeakerOn = true
  var isCompact = false
  var replyVoice: ReplyVoiceStatus?
  /// What the agent says it is doing, for the indicator under the transcript.
  var activity: String?
  /// Read by the waveforms only, so the fast changing level redraws nothing else.
  var amplitude: () -> Double = { 0.7 }
  var actions = Actions()

  @State private var position = ScrollPosition(edge: .bottom)

  var body: some View {
    if isCompact {
      CompactCallBar(
        name: name, avatar: avatar, startedAt: startedAt,
        isMuted: presentation.phase == .muted, amplitude: amplitude, onEnd: actions.end,
        onExpand: actions.expand)
    } else {
      VStack(spacing: 0) {
        CallSheetHeader(
          name: name, avatar: avatar, startedAt: startedAt, phase: presentation.phase,
          isWorking: presentation.isWorking)
        ReplyVoiceStatusView(status: replyVoice, onRetry: actions.retryReplyVoice)
        transcript
        CallControls(
          isMuted: presentation.phase == .muted, isSpeakerOn: isSpeakerOn, actions: actions)
      }
      .accessibilityIdentifier("callSheet")
    }
  }

  private var transcript: some View {
    ScrollView {
      VStack(spacing: 12) {
        Text("Voice chat started")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.bottom, 4)
        TranscriptBubbles(lines: lines)
        turn
        if presentation.offersRetry {
          Button(
            "Not listening, tap to retry", systemImage: "arrow.clockwise", action: actions.retry
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("voiceRetry")
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 16)
      .frame(maxWidth: .infinity)
    }
    .defaultScrollAnchor(.bottom)
    .scrollPosition($position)
    .onChange(of: lines) { scrollToEnd() }
    .onChange(of: presentation.turn) { scrollToEnd() }
  }

  private func scrollToEnd() {
    withAnimation { position.scrollTo(edge: .bottom) }
  }

  @ViewBuilder
  private var turn: some View {
    switch presentation.turn {
    case .speaking:
      TurnStatus(text: "Speaking", amplitude: amplitude)
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    case .listening(let words):
      MessageBubble(text: words, isFromUser: true)
      TurnStatus(text: "Listening…", amplitude: amplitude)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .trailing)
    case .thinking:
      ThinkingIndicator(avatar: avatar, name: name, label: activity)
    case nil:
      EmptyView()
    }
  }
}

struct TranscriptBubbles: View {
  let lines: [TranscriptLine]

  var body: some View {
    ForEach(lines) { line in
      MessageBubble(text: line.text, isFromUser: line.isFromUser)
    }
  }
}

/// Counts up from `startedAt`, `mm:ss`.
struct CallDuration: View {
  let startedAt: Date

  var body: some View {
    TimelineView(.periodic(from: startedAt, by: 1)) { context in
      Text(VoiceChat.duration(seconds: max(0, Int(context.date.timeIntervalSince(startedAt)))))
        .monospacedDigit()
    }
  }
}

/// `WaveformView` reading the level in its own body.
private struct LiveWaveform: View {
  let amplitude: () -> Double
  let height: CGFloat
  let barCount: Int

  var body: some View {
    WaveformView(amplitude: amplitude(), height: height, barCount: barCount)
      .foregroundStyle(.tint)
  }
}

struct CallSheetHeader: View {
  let name: String
  let avatar: Avatar
  let startedAt: Date
  let phase: CallBannerPhase
  var isWorking = false

  var body: some View {
    HStack(spacing: 10) {
      AvatarView(avatar: avatar, size: 28)
        .accessibilityHidden(true)
      Text(name)
        .font(.headline)
        .foregroundStyle(.primary)
      HStack(spacing: 5) {
        Circle()
          .fill(phase == .live ? Color.green : Color(.tertiaryLabel))
          .frame(width: 8, height: 8)
        Text(phase.accessibilityValue)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: 0)
      if isWorking {
        Text("Working…")
        Text("·")
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      CallDuration(startedAt: startedAt)
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .frame(height: 52)
    .padding(.horizontal, 20)
    .padding(.top, 20)
  }
}

/// A waveform and a word under the turn in progress.
struct TurnStatus: View {
  let text: String
  let amplitude: () -> Double

  var body: some View {
    HStack(spacing: 8) {
      LiveWaveform(amplitude: amplitude, height: 14, barCount: 7)
      Text(text)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }
}

/// Shows the Assistant working on what the user said, until its reply comes. `label` is what
/// the agent says it is doing, when it says so, and "Working…" otherwise.
struct ThinkingIndicator: View {
  let avatar: Avatar
  let name: String
  var label: String?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var announcements = AnnouncementThrottle()

  var body: some View {
    HStack(spacing: 8) {
      AvatarView(avatar: avatar, size: 28)
        .accessibilityHidden(true)
      HStack(spacing: 12) {
        TimelineView(.periodic(from: .now, by: 0.4)) { context in
          let step = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 3
          HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
              Circle()
                .frame(width: 10, height: 10)
                .opacity([1, 0.55, 0.25][(index - step + 3) % 3])
            }
          }
          .foregroundStyle(Color(.secondaryLabel))
        }
        Text(label ?? AgentActivity.defaultLabel)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .padding(.leading, 16)
      .padding(.trailing, 18)
      .frame(minHeight: 44)
      .background(Color(.secondarySystemBackground), in: Capsule())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier("thinkingIndicator")
    .onAppear(perform: announce)
    .onChange(of: label, announce)
  }

  private var accessibilityText: String {
    AgentActivity.accessibilityLabel(label, name: name)
  }

  private func announce() {
    guard label != nil, announcements.allows(at: .now) else { return }
    AccessibilityNotification.Announcement(accessibilityText).post()
  }
}

/// Mute, Speaker and End, above an empty slot kept for a push-to-talk control.
struct CallControls: View {
  let isMuted: Bool
  let isSpeakerOn: Bool
  let actions: CallSheetContent.Actions

  var body: some View {
    VStack(spacing: 16) {
      HStack {
        DockButton(
          title: isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "mic.slash.fill" : "mic",
          foreground: isMuted ? Color(.systemBackground) : .primary,
          background: isMuted ? Color(.label) : Color(.tertiarySystemFill),
          identifier: "voiceMute", action: actions.mute)
        Spacer()
        DockButton(
          title: "Speaker", systemImage: "speaker.wave.2.fill",
          foreground: isSpeakerOn ? .white : .primary,
          background: isSpeakerOn ? .accentColor : Color(.tertiarySystemFill),
          identifier: "voiceSpeaker", value: isSpeakerOn ? "On" : "Off", action: actions.speaker)
        Spacer()
        DockButton(
          title: "End", systemImage: "phone.down.fill", foreground: .white, background: .red,
          identifier: "voiceEnd", action: actions.end)
      }
      .padding(.horizontal, 20)
      Color.clear.frame(height: 72)
    }
    .padding(.top, 16)
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
  }
}

private struct DockButton: View {
  let title: String
  let systemImage: String
  let foreground: Color
  let background: Color
  let identifier: String
  var value: String?
  let action: () -> Void

  var body: some View {
    VStack(spacing: 6) {
      Button(title, systemImage: systemImage, action: action)
        .buttonStyle(.circle(foreground: foreground, background: background, diameter: 56))
        .imageScale(.large)
        .accessibilityValue(value ?? "")
        .accessibilityIdentifier(identifier)
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
    .frame(width: 72)
  }
}

/// The call sheet pulled down: the chat stays readable and usable above it.
struct CompactCallBar: View {
  let name: String
  let avatar: Avatar
  let startedAt: Date
  var isMuted = false
  var amplitude: () -> Double = { 0.7 }
  let onEnd: () -> Void
  let onExpand: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      AvatarView(avatar: avatar, size: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 0) {
        Text(name)
          .font(.headline)
          .lineLimit(1)
        CallDuration(startedAt: startedAt)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      LiveWaveform(amplitude: { isMuted ? 0 : amplitude() }, height: 24, barCount: 18)
        .frame(maxWidth: .infinity)
      Button("End", systemImage: "phone.down.fill", action: onEnd)
        .buttonStyle(.circle(foreground: .white, background: .red, diameter: 44))
        .accessibilityIdentifier("voiceEnd")
    }
    .padding(.leading, 20)
    .padding(.trailing, 16)
    .frame(height: 64)
    .padding(.top, 20)
    .frame(maxHeight: .infinity, alignment: .top)
    .contentShape(Rectangle())
    .onTapGesture(perform: onExpand)
    .accessibilityElement(children: .contain)
    .accessibilityAction(named: "Expand", onExpand)
    .accessibilityIdentifier("compactCallBar")
  }
}

/// The transcript of an ended voice chat, which its timeline entry opens.
struct VoiceTranscriptSheet: View {
  let chat: VoiceChatRecord

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 12) {
      ZStack {
        Text(VoiceChat.text(seconds: chat.seconds))
          .font(.headline)
        Button("Close", systemImage: "xmark") { dismiss() }
          .buttonStyle(.circle(diameter: 44))
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("closeTranscript")
      }
      .frame(height: 52)
      .padding(.horizontal, 16)
      .padding(.top, 20)
      ScrollView {
        VStack(spacing: 12) {
          TranscriptBubbles(lines: chat.lines)
          if let footer {
            Text(footer)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .padding(.top, 12)
          }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }

  private var footer: String? {
    guard let startedAt = chat.startedAt else { return nil }
    let date = startedAt.formatted(.dateTime.day().month(.abbreviated).year())
    return chat.seconds.map { "\(date) · \(VoiceChat.duration(seconds: $0))" } ?? date
  }
}

extension TranscriptLine {
  static let samples: [TranscriptLine] = [
    TranscriptLine(id: "1", text: "What’s on my calendar this afternoon?", isFromUser: true),
    TranscriptLine(
      id: "2", text: "You have the design review at 3, and nothing after that.", isFromUser: false),
    TranscriptLine(
      id: "3", text: "Move the design review to 4, and text Dana I’ll be a few minutes late.",
      isFromUser: true),
    TranscriptLine(
      id: "4", text: "Done. The design review is at 4, and I sent Dana a message.",
      isFromUser: false),
  ]
}

private func sampleSheet(
  _ state: VoiceCall.State, heard: String = "", lines: [TranscriptLine] = TranscriptLine.samples,
  seconds: TimeInterval, activity: String? = nil
) -> some View {
  CallSheetContent(
    name: "Hermes", avatar: Avatar(id: "avatar-3"), startedAt: .now.addingTimeInterval(-seconds),
    lines: lines,
    presentation: CallSheetPresentation(
      state: state, isMuted: false, listeningFailed: false, heard: heard, transcript: lines),
    activity: activity)
}

private func activitySheet() -> some View {
  sampleSheet(
    .listening, lines: Array(TranscriptLine.samples.prefix(3)), seconds: 62,
    activity: "Moving the design review…")
}

#Preview("Call sheet, speaking") { sampleSheet(.speaking, seconds: 48) }
#Preview("Call sheet, listening") {
  sampleSheet(.listening, heard: "And can you also add bread to the list?", seconds: 52)
}
#Preview("Call sheet, thinking") {
  sampleSheet(.listening, lines: Array(TranscriptLine.samples.prefix(3)), seconds: 62)
}
#Preview("Call sheet, thinking, dark") {
  sampleSheet(.listening, lines: Array(TranscriptLine.samples.prefix(3)), seconds: 62)
    .preferredColorScheme(.dark)
}
#Preview("Call sheet, activity") { activitySheet() }
#Preview("Call sheet, activity, dark") { activitySheet().preferredColorScheme(.dark) }
#Preview("Call sheet, collapsed") {
  CompactCallBar(
    name: "Hermes", avatar: Avatar(id: "avatar-3"), startedAt: .now.addingTimeInterval(-68),
    onEnd: {}, onExpand: {}
  )
  .frame(height: CallSheet.compactHeight)
}
#Preview("Voice chat transcript") {
  VoiceTranscriptSheet(
    chat: VoiceChatRecord(
      id: "e", startedAt: .now, seconds: 72, lines: TranscriptLine.samples))
}
