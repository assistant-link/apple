import SwiftUI

/// The design of dictation in the message field, after the Grok app: the words fill the field as
/// the user speaks, and they send them as they are or stop and fix them first. `ComposerView`
/// drives it with `Dictation`; the previews and the component catalog show it on sample data.
struct DictationComposer: View {
  enum Phase: Equatable {
    case idle
    case preparing
    case recording(seconds: Int)
    /// The microphone stopped; the last words may still change.
    case finishing
    /// Recording stopped; the words stay in the field to fix before sending.
    case editing
  }

  let phase: Phase
  var assistantName = "Hermes"
  /// Words the recognizer settled on.
  var confirmed = ""
  /// The words it may still change, drawn lighter and in italics.
  var provisional = ""
  /// Recent microphone levels, 0 to 1, oldest first.
  var levels: [Float] = []
  var onSend: () -> Void = {}
  var onStop: () -> Void = {}

  static let maxLines = 6

  var body: some View {
    if case .recording(let seconds) = phase {
      recording(seconds: seconds)
    } else {
      bar
    }
  }

  private var bar: some View {
    HStack(alignment: .bottom, spacing: 8) {
      Button("Attach", systemImage: "plus") {}
        .buttonStyle(.circle())
        .disabled(true)
        .accessibilityIdentifier("attachButton")
      field
        .padding(.vertical, 11)
      if phase == .editing {
        SendButton(action: onSend)
      } else if phase == .finishing {
        ProgressView()
          .frame(width: 44, height: 44)
          .accessibilityIdentifier("finishingDictation")
      } else {
        Button("Dictate", systemImage: "mic") {}
          .buttonStyle(.circle())
          .disabled(phase == .preparing)
          .accessibilityIdentifier("dictationButton")
      }
    }
    .composerBox()
  }

  @ViewBuilder
  private var field: some View {
    switch phase {
    case .idle:
      Text("Ask \(assistantName)")
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    case .preparing:
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text("Preparing").foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    case .editing, .recording, .finishing:
      transcript
    }
  }

  /// The words across the full width, over a row with stop where attach was and send where the
  /// dictation button was.
  private func recording(seconds: Int) -> some View {
    VStack(spacing: 10) {
      transcript
        .padding(.horizontal, 10)
        .padding(.top, 10)
      HStack(spacing: 8) {
        Button("Stop", systemImage: "stop.fill", action: onStop)
          .buttonStyle(.circle())
          .accessibilityIdentifier("stopDictationButton")
        Text(Self.elapsed(seconds))
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
        Waveform(levels: levels)
          .frame(maxWidth: .infinity)
        SendButton(action: onSend)
      }
    }
    .composerBox()
  }

  /// Up to six lines, then it scrolls and keeps the newest words in view.
  private var transcript: some View {
    ScrollView {
      Text(Self.transcript(confirmed: confirmed, provisional: provisional))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .defaultScrollAnchor(.bottom)
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxHeight: Self.lineHeight * CGFloat(Self.maxLines))
    // Takes the height of the text, up to the limit, rather than all of it.
    .fixedSize(horizontal: false, vertical: true)
  }

  private static var lineHeight: CGFloat { UIFont.preferredFont(forTextStyle: .body).lineHeight }

  static func transcript(confirmed: String, provisional: String) -> AttributedString {
    var result = AttributedString(confirmed)
    guard !provisional.isEmpty else { return result }
    var tail = AttributedString((confirmed.isEmpty ? "" : " ") + provisional)
    tail.swiftUI.foregroundColor = .secondary
    tail.swiftUI.font = .body.italic()
    result += tail
    return result
  }

  static func elapsed(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}

/// Grey bars that follow the microphone level, newest on the right.
private struct Waveform: View {
  let levels: [Float]

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
        Capsule()
          .fill(.secondary)
          .frame(width: 3, height: 4 + 20 * CGFloat(level))
      }
    }
    .frame(height: 24)
    .accessibilityHidden(true)
  }
}

extension DictationComposer {
  static let sampleLevels: [Float] = [
    0.1, 0.2, 0.15, 0.4, 0.7, 0.55, 0.9, 0.6, 0.35, 0.5, 0.8, 0.45, 0.3, 0.6, 0.75, 0.4, 0.2,
    0.35, 0.55, 0.25, 0.1, 0.3, 0.5, 0.2,
  ]
  static let sampleConfirmed = "Remind me to call David tomorrow"
  static let sampleProvisional = "at nine and"
  static let sampleLongConfirmed = """
    Remind me to call David tomorrow at nine about the launch, and add it to my calendar so I \
    do not forget. Also ask him whether the designs are ready, because the team needs them \
    before Thursday, and tell him the budget was approved this morning by finance after the \
    review we had last week with
    """
  static let sampleLongProvisional = "the whole product team"
}

#Preview("Dictation") {
  VStack(spacing: 16) {
    DictationComposer(phase: .idle)
    DictationComposer(phase: .preparing)
    DictationComposer(
      phase: .recording(seconds: 4), confirmed: DictationComposer.sampleConfirmed,
      provisional: DictationComposer.sampleProvisional, levels: DictationComposer.sampleLevels)
    DictationComposer(
      phase: .editing,
      confirmed: DictationComposer.sampleConfirmed + " at nine and add it to my calendar")
  }
  .padding()
}

#Preview("Dictation, six lines") {
  VStack {
    DictationComposer(
      phase: .recording(seconds: 27), confirmed: DictationComposer.sampleLongConfirmed,
      provisional: DictationComposer.sampleLongProvisional, levels: DictationComposer.sampleLevels)
  }
  .padding()
}
