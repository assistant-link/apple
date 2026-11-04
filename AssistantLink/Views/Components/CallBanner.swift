import SwiftUI

/// The voice chat controls below the navigation bar: mute and end.
struct CallBanner: View {
  let phase: CallBannerPhase
  let avatar: Avatar
  /// How lively the bars are while live, 0 to 1. Read in this view's body so that the fast
  /// changing level redraws only the banner.
  var amplitude: () -> Double = { 0.7 }
  let onMute: () -> Void
  let onEnd: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      AvatarView(avatar: avatar, size: 36)
      waveform
        .frame(maxWidth: .infinity)
      Button(
        phase == .muted ? "Unmute" : "Mute",
        systemImage: phase == .muted ? "mic.slash" : "mic", action: onMute
      )
      .labelStyle(.iconOnly)
      .buttonStyle(.plain)
      .foregroundStyle(phase == .muted ? Color(.systemBackground) : Color.primary)
      .frame(width: 40, height: 40)
      .background {
        if phase == .muted {
          Circle().fill(Color(.label))
        } else {
          Circle().fill(Color(.tertiarySystemFill))
        }
      }
      .accessibilityIdentifier("voiceMute")
      Button("End", systemImage: "xmark", action: onEnd)
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
        .background(.red, in: Circle())
        .accessibilityIdentifier("voiceEnd")
    }
    .padding(.horizontal, 14)
    .frame(height: 64)
    .glassBackground(in: Capsule())
  }

  @ViewBuilder
  private var waveform: some View {
    if phase == .live {
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
