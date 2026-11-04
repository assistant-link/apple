import SwiftUI

/// The Assistant's avatar, name and status in the navigation bar.
struct TitleBubble: View {
  enum Status {
    case online
    case offline
    /// Tinted red, with a waveform next to the name.
    case inCall

    var statusText: String? {
      switch self {
      case .online: "Online"
      case .offline: "Offline"
      case .inCall: nil
      }
    }

    var accessibilityValue: String {
      switch self {
      case .online: "Online"
      case .offline: "Offline"
      case .inCall: "In a voice chat"
      }
    }
  }

  let name: String
  let avatar: Avatar
  let status: Status

  var body: some View {
    HStack(spacing: 8) {
      AvatarView(avatar: avatar, size: 28, isOnline: status == .online)
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
