import SwiftUI

/// The Assistant's avatar, name and status in the navigation bar.
struct TitleBubble: View {
  enum State {
    case online
    case offline
    /// Tinted red, with the name only.
    case inCall

    var statusText: String? {
      switch self {
      case .online: "Online"
      case .offline: "Offline"
      case .inCall: nil
      }
    }
  }

  let name: String
  let avatar: Avatar
  let state: State

  var body: some View {
    HStack(spacing: 8) {
      AvatarView(avatar: avatar, size: 28, isOnline: state == .online)
      VStack(alignment: .leading, spacing: 0) {
        Text(name)
          .font(.headline)
          .lineLimit(1)
        if let status = state.statusText {
          Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 6)
    .padding(.leading, 6)
    .padding(.trailing, 14)
    .glassBackground(in: Capsule(), tint: state == .inCall ? .red.opacity(0.4) : nil)
    .accessibilityElement(children: .combine)
  }
}
