import SwiftUI

/// The Assistant's avatar, name and status in the navigation bar.
struct TitleBubble: View {
  enum Status {
    case online
    case idle
    case offline
    case inCall

    var statusText: String {
      self == .inCall ? "In call" : assistantStatus.label
    }

    var accessibilityValue: String { statusText }

    /// The avatar badge; a call shows green, like the live badge in the call sheet.
    var assistantStatus: Assistant.Status {
      switch self {
      case .online, .inCall: .online
      case .idle: .idle
      case .offline: .offline
      }
    }
  }

  let name: String
  let avatar: Avatar
  let status: Status

  var body: some View {
    HStack(spacing: 8) {
      AvatarView(avatar: avatar, size: 28, status: status.assistantStatus)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 0) {
        Text(name)
          .font(.headline)
          .lineLimit(1)
        Text(status.statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 6)
    .padding(.leading, 6)
    .padding(.trailing, 14)
    .glassBackground(in: Capsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(name)
    .accessibilityValue(status.accessibilityValue)
  }
}
