import UIKit

enum BackgroundTime {
  /// Holds a background assertion until `task` finishes or the system takes the time back.
  @MainActor
  static func keepRunning(_ task: Task<Void, Never>) {
    var identifier = UIBackgroundTaskIdentifier.invalid
    identifier = UIApplication.shared.beginBackgroundTask(withName: "call-ended") {
      UIApplication.shared.endBackgroundTask(identifier)
      identifier = .invalid
    }
    Task { @MainActor in
      await task.value
      if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
    }
  }
}
