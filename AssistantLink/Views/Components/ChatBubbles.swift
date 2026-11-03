import SwiftUI

struct ChatBubble: View {
  enum Style {
    case incoming
    case outgoing
    case deleted
  }

  let text: String
  let style: Style

  var body: some View {
    Text(text)
      .italic(style == .deleted)
      .foregroundStyle(foreground)
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .background(background, in: RoundedRectangle(cornerRadius: 18))
  }

  private var foreground: Color {
    switch style {
    case .incoming: .primary
    case .outgoing: .white
    case .deleted: .secondary
    }
  }

  private var background: Color {
    switch style {
    case .incoming: Color(.secondarySystemBackground)
    case .outgoing: .accentColor
    case .deleted: Color(.secondarySystemFill)
    }
  }
}

/// The red badge next to an outgoing message that was not delivered.
struct FailureBadge: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "exclamationmark.circle.fill")
        .font(.title3)
        .foregroundStyle(.red)
    }
    .accessibilityLabel("Not Delivered")
    .accessibilityIdentifier("failedMessage")
  }
}

/// The line under the latest outgoing message.
struct DeliveryCaption: View {
  let caption: MessageCaption
  var isVoice = false

  var body: some View {
    HStack(spacing: 4) {
      if isVoice {
        Image(systemName: "mic.fill")
          .accessibilityLabel("Voice")
      }
      Text(caption.text)
    }
    .font(.caption)
    .foregroundStyle(caption == .notDelivered ? Color.red : Color.secondary)
    .padding(.horizontal, 4)
  }
}

struct TimeCaptionView: View {
  let date: Date

  var body: some View {
    Text(TimeCaption.text(for: date))
      .font(.footnote)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
  }
}

/// The date, then the name of the Link that was created.
struct SystemEventCaption: View {
  let date: Date
  let linkName: String

  var body: some View {
    VStack(spacing: 2) {
      TimeCaptionView(date: date)
      Label(linkName, systemImage: "link")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}
