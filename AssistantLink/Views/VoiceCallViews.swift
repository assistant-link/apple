import SwiftUI

/// Bars that move with `amplitude` (0 to 1).
struct WaveformView: View {
  let amplitude: Double
  let height: CGFloat
  var barWidth: CGFloat = 3

  private static let barCount = 5

  var body: some View {
    TimelineView(.animation) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      HStack(spacing: barWidth) {
        ForEach(0..<Self.barCount, id: \.self) { index in
          let wave = abs(sin(time * 6 + Double(index) * 0.9))
          Capsule()
            .frame(width: barWidth, height: height * (0.2 + 0.8 * amplitude * wave))
        }
      }
      .frame(height: height)
    }
    .accessibilityHidden(true)
  }
}

extension VoiceCall {
  /// How lively the waveform is: the voice while listening, a steady motion while speaking.
  var amplitude: Double {
    switch state {
    case .idle, .connecting: 0
    case .speaking: 0.7
    case .listening: isMuted ? 0 : max(0.1, Double(level))
    }
  }
}

/// The red capsule in the navigation bar while a voice chat is on.
struct VoiceCallPill: View {
  let call: VoiceCall
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      pillContent
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.red, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Voice chat")
    .accessibilityHint("Shows the voice chat controls")
    .accessibilityIdentifier("voicePill")
  }

  @ViewBuilder
  private var pillContent: some View {
    if call.state == .connecting {
      Text("Connecting…")
        .font(.caption.bold())
    } else {
      WaveformView(amplitude: call.amplitude, height: 14)
    }
  }
}

/// The voice chat controls, at the top of the conversation.
struct VoiceCallBanner: View {
  let call: VoiceCall
  let assistantName: String
  let onCollapse: () -> Void
  let onEnd: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text(assistantName)
          .font(.headline)
        Spacer()
        Button("Hide", systemImage: "chevron.up", action: onCollapse)
          .labelStyle(.iconOnly)
          .accessibilityIdentifier("voiceCollapse")
      }
      if call.state == .connecting {
        Text("Connecting…")
          .foregroundStyle(.secondary)
          .frame(height: 44)
      } else {
        WaveformView(amplitude: call.amplitude, height: 44, barWidth: 6)
          .foregroundStyle(.red)
      }
      HStack(spacing: 12) {
        Button(
          call.isMuted ? "Unmute" : "Mute",
          systemImage: call.isMuted ? "mic.slash.fill" : "mic.fill"
        ) {
          call.setMuted(!call.isMuted)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("voiceMute")
        Button("End", systemImage: "phone.down.fill", action: onEnd)
          .buttonStyle(.borderedProminent)
          .tint(.red)
          .accessibilityIdentifier("voiceEnd")
      }
    }
    .padding()
    .background(.bar)
  }
}

/// A small caption under the last message of a voice chat; not a bubble.
struct VoiceChatCaption: View {
  let seconds: Int?

  var body: some View {
    Label(VoiceChat.text(seconds: seconds), systemImage: "waveform")
      .font(.footnote)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
  }
}
