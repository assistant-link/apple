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
