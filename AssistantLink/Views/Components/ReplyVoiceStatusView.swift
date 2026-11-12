import SwiftUI

/// A small caption under the call controls while Kokoro is not ready yet, and briefly once it is.
struct ReplyVoiceStatusView: View {
  /// Nil when the replies are not read with Kokoro.
  let status: ReplyVoiceStatus?
  let onRetry: () -> Void

  @State private var confirmsReady = false

  var body: some View {
    // Not a Group, which would hand the modifiers below to its children, of which there are none
    // when the notice is about to become the ready confirmation.
    VStack(spacing: 0) {
      if let notice = ReplyVoiceNotice(status, confirmsReady: confirmsReady) {
        caption(notice)
          .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.3), value: status)
    .animation(.easeInOut(duration: 0.3), value: confirmsReady)
    .onChange(of: status) { old, new in
      if new == .ready, let old, old != .ready { confirmsReady = true }
    }
    .task(id: confirmsReady) {
      guard confirmsReady else { return }
      try? await Task.sleep(for: .seconds(3))
      confirmsReady = false
    }
  }

  private func caption(_ notice: ReplyVoiceNotice) -> some View {
    HStack(spacing: 6) {
      if notice.isUnderway {
        ProgressView()
          .controlSize(.mini)
      } else if notice == .ready {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
      } else {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
      }
      Text(notice.text)
        .monospacedDigit()
      if notice.offersRetry {
        Button("Retry", action: onRetry)
          .font(.caption.weight(.semibold))
          .accessibilityIdentifier("replyVoiceRetry")
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .glassBackground(in: Capsule())
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("replyVoiceStatus")
  }
}
