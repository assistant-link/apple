import UIKit
import UserNotifications

/// Owns the model, so a push tapped while the app is not running reaches it before any view
/// exists.
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  let model = AppModel.live()

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return true
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    model.received(pushToken: deviceToken)
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: any Error
  ) {
    PushNotifications.logger.notice(
      "APNs registration failed: \(error.localizedDescription, privacy: .public)")
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let push = Push(userInfo: notification.request.content.userInfo)
    return await model.showsBanner(for: push) ? [.banner, .list, .sound] : []
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let push = Push(userInfo: response.notification.request.content.userInfo)
    await model.open(push)
  }
}
