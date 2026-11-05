import SwiftUI

/// The voice chat controls below the navigation bar: mute, end, and retry listening.
struct CallBanner: View {
  let phase: CallBannerPhase
  let avatar: Avatar
  /// How lively the bars are while the mic is live, 0 to 1. Read in this view's body so that the
  /// fast changing level redraws only the banner.
  var amplitude: () -> Double = { 0.7 }
  let onRetry: () -> Void
  let onMute: () -> Void
  let onEnd: () -> Void

  private var isMuted: Bool { phase == .muted }

  var body: some View {
    HStack(spacing: 12) {
      AvatarView(avatar: avatar, size: 36)
        .accessibilityHidden(true)
      waveform
        .frame(maxWidth: .infinity)
      Button(
        isMuted ? "Unmute" : "Mute",
        systemImage: isMuted ? "mic.slash" : "mic", action: onMute
      )
      .buttonStyle(
        .circle(
          foreground: isMuted ? Color(.systemBackground) : .primary,
          background: isMuted ? Color(.label) : Color(.tertiarySystemFill), diameter: 40)
      )
      .accessibilityIdentifier("voiceMute")
      Button("End voice chat", systemImage: "xmark", action: onEnd)
        .buttonStyle(.circle(foreground: .white, background: .red, diameter: 40))
        .accessibilityIdentifier("voiceEnd")
    }
    .padding(.horizontal, 14)
    .frame(height: 64)
    .glassBackground(in: Capsule())
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Voice chat")
    .accessibilityIdentifier("callBanner")
    .accessibilityValue(phase.accessibilityValue)
  }

  @ViewBuilder
  private var waveform: some View {
    if phase == .notListening {
      Button(action: onRetry) {
        Label("Not listening, tap to retry", systemImage: "arrow.clockwise")
          .font(.subheadline)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 40)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("voiceRetry")
    } else if phase.showsWaveform {
      WaveformView(
        amplitude: max(amplitude(), 0.4), height: 28, barWidth: 2, barCount: 32, growing: true
      )
      .foregroundStyle(.red)
    } else {
      DottedLine()
        .stroke(
          Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 6])
        )
        .frame(height: 8)
        .accessibilityHidden(true)
    }
  }
}

private struct DottedLine: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
    }
  }
}
