import SwiftUI

struct ChatBubble: View {
  enum Style {
    case incoming
    case outgoing
    case deleted
  }

  let text: String
  let style: Style
  /// The start of the message this one answers.
  var quote: String?
  var onQuoteTap: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let quote {
        let block = QuoteBlock(text: quote, isOutgoing: style == .outgoing)
        Group {
          if let onQuoteTap {
            Button(action: onQuoteTap) { block }
              .buttonStyle(.plain)
              .accessibilityHint("Shows the message")
          } else {
            block
          }
        }
        .accessibilityLabel("Reply to: \(quote)")
        .accessibilityIdentifier("replyQuote")
        .padding([.top, .horizontal], 6)
      }
      Text(text)
        .italic(style == .deleted)
        .foregroundStyle(foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
    .background(background, in: RoundedRectangle(cornerRadius: 18))
    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18))
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

/// One line of the message a reply answers, at the top of the reply's bubble.
struct QuoteBlock: View {
  let text: String
  let isOutgoing: Bool

  /// Darker than the outgoing bubble's tint.
  private static let outgoingBackground = Color(red: 0, green: 0x62 / 255, blue: 0xD1 / 255)
  /// A shade darker than the incoming bubble.
  private static let incomingBackground = Color(
    UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)
        : UIColor(red: 0xE3 / 255, green: 0xE3 / 255, blue: 0xE8 / 255, alpha: 1)
    })

  var body: some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 1.5)
        .fill(isOutgoing ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.tint))
        .frame(width: 3)
      Text(text)
        .font(.subheadline)
        .lineLimit(1)
        .foregroundStyle(
          isOutgoing ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.leading, 8)
    .padding(.trailing, 10)
    .padding(.vertical, 6)
    .background(
      isOutgoing ? Self.outgoingBackground : Self.incomingBackground,
      in: RoundedRectangle(cornerRadius: 12))
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

/// Above the first message that arrived since the user last read the conversation.
struct UnreadDivider: View {
  var body: some View {
    HStack(spacing: 12) {
      line
      Text("NEW")
        .font(.footnote.weight(.semibold))
      line
    }
    .foregroundStyle(.tint)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("New messages")
    .accessibilityIdentifier("unreadDivider")
  }

  private var line: some View {
    Rectangle().frame(height: 1)
  }
}

/// The date, then that a Link was created and its name.
struct SystemEventCaption: View {
  let date: Date
  let linkName: String

  static func text(linkName: String) -> String {
    "Assistant Link created · \(linkName)"
  }

  var body: some View {
    VStack(spacing: 2) {
      TimeCaptionView(date: date)
      Label(Self.text(linkName: linkName), systemImage: "link")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}
