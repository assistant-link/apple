/// What a call shows of Kokoro getting ready, since Apple voice reads the replies until it is.
enum ReplyVoiceNotice: Equatable {
  case downloading(percent: Int?)
  case preparing
  case ready
  case failed

  /// `status` is nil when the replies are not read with Kokoro. Ready shows only while
  /// `confirmsReady`, briefly after the voice got ready during the call.
  init?(_ status: ReplyVoiceStatus?, confirmsReady: Bool) {
    switch status {
    case nil: return nil
    case .downloading(let fraction):
      self = .downloading(percent: fraction.map { Int(($0 * 100).rounded(.down)) })
    case .notStarted, .preparing: self = .preparing
    case .ready:
      guard confirmsReady else { return nil }
      self = .ready
    case .failed: self = .failed
    }
  }

  var text: String {
    switch self {
    case .downloading(let percent?): "Downloading Kokoro voice… \(percent)%"
    case .downloading(nil): "Downloading Kokoro voice…"
    case .preparing: "Preparing Kokoro voice…"
    case .ready: "Kokoro voice ready"
    case .failed: "Kokoro voice unavailable"
    }
  }

  var isUnderway: Bool {
    switch self {
    case .downloading, .preparing: true
    case .ready, .failed: false
    }
  }

  var offersRetry: Bool { self == .failed }
}
