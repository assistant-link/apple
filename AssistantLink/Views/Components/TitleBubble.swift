import SwiftUI

/// The Assistant's avatar, name and status in the navigation bar.
struct TitleBubble: View {
  enum Status {
    case online
    case idle
    case offline
    case inCall

    var statusText: String? {
      assistantStatus?.label
    }

    var accessibilityValue: String {
      statusText ?? "In a voice chat"
    }

    /// `nil` in a call, which the title shows instead.
    var assistantStatus: Assistant.Status? {
      switch self {
      case .online: .online
      case .idle: .idle
      case .offline: .offline
      case .inCall: nil
      }
    }
  }

  let name: String
  let avatar: Avatar
  let status: Status

  var body: some View {
    HStack(spacing: 8) {
      AvatarView(avatar: avatar, size: 28, status: status.assistantStatus ?? .offline)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 4) {
          Text(name)
            .font(.headline)
            .lineLimit(1)
          if status == .inCall {
            Image(systemName: "waveform")
              .font(.subheadline)
              .foregroundStyle(.red)
          }
        }
        if let status = status.statusText {
          Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 6)
    .padding(.leading, 6)
    .padding(.trailing, 14)
    .glassBackground(in: Capsule(), tint: status == .inCall ? .red.opacity(0.4) : nil)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(name)
    .accessibilityValue(status.accessibilityValue)
  }
}
