@testable import AssistantLink

@MainActor
final class FakeDictationListener: SpeechListener {
  var vocabulary: [String] = []
  var startError: (any Error)?
  private(set) var starts = 0
  private(set) var stops = 0
  private var handler: (@MainActor (SpeechEvent) -> Void)?

  func start(_ handler: @escaping @MainActor (SpeechEvent) -> Void) throws {
    if let startError { throw startError }
    starts += 1
    self.handler = handler
  }

  func stop() {
    stops += 1
    handler = nil
  }

  func hear(_ event: SpeechEvent) { handler?(event) }
}

@MainActor
final class FakeDictationAudio: VoiceAudio {
  var isAllowed = true
  private(set) var isActive = false

  /// While set, `requestPermission` waits until `answer` is called.
  var holdsPermission = false
  private var pending: [CheckedContinuation<Bool, Never>] = []

  func requestPermission() async -> Bool {
    guard holdsPermission else { return isAllowed }
    return await withCheckedContinuation { pending.append($0) }
  }

  func answer(_ allowed: Bool) {
    guard !pending.isEmpty else { return }
    pending.removeFirst().resume(returning: allowed)
  }

  func activate() throws { isActive = true }
  func observeRouteChanges(_ handler: @escaping @MainActor () -> Void) {}
  func deactivate() { isActive = false }
}

extension Dictation {
  /// What every test that builds an `AppModel` passes, so none opens the real recognizer or audio session.
  @MainActor
  static func fake() -> Dictation {
    Dictation(listener: FakeDictationListener(), audio: FakeDictationAudio())
  }
}
