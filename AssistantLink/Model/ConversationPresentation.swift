import Foundation

extension Assistant {
  /// Messages can only be sent to an Assistant with a Link that has been paired.
  var hasPairedLink: Bool {
    links.contains { $0.status != .notPaired }
  }

  var showsComposer: Bool { hasPairedLink }

  /// Shown above the composer while messages wait for the Assistant to connect.
  var offlineNotice: String? {
    guard status == .offline, hasPairedLink else { return nil }
    return "\(name) is offline. Messages will be delivered when it connects."
  }
}

/// The latest event line of an Assistants list entry.
struct ListPreview: Equatable {
  var text: String
  /// Whether the user's message failed and was never stored.
  var isFailed = false

  init(event: Event?, failedMessage: OutgoingMessage?) {
    if let failedMessage {
      self.init(text: "You: \(failedMessage.text)", isFailed: true)
      return
    }
    guard let event else {
      self.init(text: "Set up a Link to connect your agent")
      return
    }
    switch event.type {
    case .linkCreated:
      self.init(text: "Assistant Link created")
    case .textMessage:
      let text = event.deleted ? "This message was deleted" : event.text ?? ""
      self.init(text: event.sender == .user ? "You: \(text)" : text)
    }
  }

  private init(text: String, isFailed: Bool = false) {
    self.text = text
    self.isFailed = isFailed
  }
}
