import Foundation

/// What an agent says it is doing, as the working indicator shows it.
enum AgentActivity {
  static let defaultLabel = "Working…"
  /// The service and `al` cut the text to the same length.
  static let maxLength = 60

  /// The text on one line and at most `maxLength` characters, or `nil` when blank.
  static func text(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let line = raw.split(whereSeparator: { $0.isWhitespace || $0.isControl })
      .joined(separator: " ")
    guard !line.isEmpty else { return nil }
    guard line.count > maxLength else { return line }
    return line.prefix(maxLength - 1).trimmingCharacters(in: .whitespaces) + "…"
  }

  static func accessibilityLabel(_ activity: String?, name: String) -> String {
    guard let activity else { return "Working" }
    return "\(name): \(activity.replacing(/(…|\.\.\.)$/, with: ""))"
  }
}

/// Activity text as `AgentActivity.text` makes it, whether set or decoded. Text this app can't
/// decode is no activity.
@propertyWrapper
struct ActivityText: Decodable, Equatable, Sendable {
  private var text: String?

  var wrappedValue: String? {
    get { text }
    set { text = AgentActivity.text(newValue) }
  }

  init(wrappedValue: String?) {
    text = AgentActivity.text(wrappedValue)
  }

  init(from decoder: any Decoder) throws {
    self.init(wrappedValue: try? decoder.singleValueContainer().decode(String.self))
  }
}

extension KeyedDecodingContainer {
  /// Synthesized decoding would otherwise require the key.
  func decode(_ type: ActivityText.Type, forKey key: Key) -> ActivityText {
    ActivityText(wrappedValue: try? decodeIfPresent(String.self, forKey: key))
  }
}

extension Assistant {
  /// The activity of its first Link that has one.
  var activity: String? { links.lazy.compactMap(\.activity).first }
}

/// Lets VoiceOver announce a new activity at most once every few seconds, so it isn't flooded.
/// What arrives in between waits, and only the latest of it is announced when the interval ends.
struct AnnouncementThrottle {
  enum Step: Equatable {
    case announce(String)
    case wait(TimeInterval)
    case none
  }

  static let interval: TimeInterval = 5
  private var lastAnnounced: Date?
  private var pending: String?

  /// After `.wait`, call `flush(at:)` once the delay has passed.
  mutating func receive(_ text: String, at date: Date) -> Step {
    if let lastAnnounced, date.timeIntervalSince(lastAnnounced) < Self.interval {
      defer { pending = text }
      return pending == nil ? .wait(Self.interval - date.timeIntervalSince(lastAnnounced)) : .none
    }
    lastAnnounced = date
    pending = nil
    return .announce(text)
  }

  mutating func flush(at date: Date) -> String? {
    guard let text = pending else { return nil }
    pending = nil
    lastAnnounced = date
    return text
  }

  mutating func cancel() { pending = nil }
}

extension Character {
  fileprivate var isControl: Bool {
    unicodeScalars.contains { $0.properties.generalCategory == .control }
  }
}
