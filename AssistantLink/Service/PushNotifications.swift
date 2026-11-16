import OSLog
import UIKit
import UserNotifications

enum PushNotifications {
  static let logger = Logger(subsystem: "ai.assistantlink.app", category: "push")

  /// Asks for permission the first time only; afterwards the system answers without asking.
  /// Once allowed, APNs hands the token to `AppDelegate`.
  @MainActor
  static func enable() {
    Task {
      let center = UNUserNotificationCenter.current()
      do {
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
        UIApplication.shared.registerForRemoteNotifications()
      } catch {
        logger.notice(
          "Notification permission failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// The service takes the APNs token as hex.
  static func hex(_ token: Data) -> String {
    token.map { String(format: "%02x", $0) }.joined()
  }
}

/// What the app reads from a push. A missing or unexpected value reads as nil, so a push from a
/// newer service still shows its banner and its tap still opens the app.
struct Push: Equatable, Sendable {
  var assistantID: Assistant.ID?
}

extension Push {
  init(userInfo: [AnyHashable: Any]) {
    self.init(assistantID: userInfo["assistant_id"] as? String)
  }
}
