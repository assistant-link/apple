import AVFoundation
import Speech

extension VoiceCall {
  static func live() -> VoiceCall {
    VoiceCall(listener: LiveSpeechListener(), speaker: LiveSpeechSpeaker(), audio: LiveVoiceAudio())
  }
}

@MainActor
final class LiveVoiceAudio: VoiceAudio {
  private var routeObserver: (any NSObjectProtocol)?

  func requestPermission() async -> Bool {
    guard await AVAudioApplication.requestRecordPermission() else { return false }
    return await Self.speechAuthorization() == .authorized
  }

  /// Nonisolated, because the system calls the handler on a background queue.
  private nonisolated static func speechAuthorization() async
    -> SFSpeechRecognizerAuthorizationStatus
  {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
  }

  func activate() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord, mode: .voiceChat,
      options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
    try session.setActive(true)
  }

  /// Only these reasons change the devices; a category change is our own `activate()`.
  nonisolated static func affectsMicrophone(_ reason: AVAudioSession.RouteChangeReason) -> Bool {
    switch reason {
    case .newDeviceAvailable, .oldDeviceUnavailable, .override, .routeConfigurationChange:
      true
    default:
      false
    }
  }

  func observeRouteChanges(_ handler: @escaping @MainActor () -> Void) {
    stopObserving()
    routeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { notification in
      let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
      guard let value, let reason = AVAudioSession.RouteChangeReason(rawValue: value),
        Self.affectsMicrophone(reason)
      else { return }
      MainActor.assumeIsolated { handler() }
    }
  }

  private func stopObserving() {
    if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    routeObserver = nil
  }

  func deactivate() {
    stopObserving()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

enum SpeechListenerError: Error {
  case recognizerUnavailable
}

/// Recognizes speech from the microphone, on the device when the language supports it.
@MainActor
final class LiveSpeechListener: SpeechListener {
  var vocabulary: [String] = []
  private let engine = AVAudioEngine()
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  /// Tells results of a recognition that was stopped from those of the current one.
  private var generation = 0

  func start(_ handler: @escaping @MainActor (SpeechEvent) -> Void) throws {
    stop()
    guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
      throw SpeechListenerError.recognizerUnavailable
    }
    self.recognizer = recognizer
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    request.contextualStrings = vocabulary
    let generation = generation
    let deliver: @Sendable (SpeechEvent) -> Void = { [weak self] event in
      Task { @MainActor in
        guard let self, self.generation == generation else { return }
        handler(event)
      }
    }
    let input = engine.inputNode
    // A route still switching reports no sample rate, which `installTap` can't take.
    guard input.outputFormat(forBus: 0).sampleRate > 0 else {
      throw SpeechListenerError.recognizerUnavailable
    }
    let tap = MicrophoneTap(request: request, deliver: deliver)
    input.installTap(
      onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.block(of: tap))
    do {
      engine.prepare()
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      throw error
    }
    self.request = request
    task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(deliver))
  }

  func stop() {
    generation += 1
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
  }

  // The system calls these from background queues, so they must not be isolated to the main
  // actor, which closures made in a main actor method would be.
  private nonisolated static func block(
    of tap: MicrophoneTap
  ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
    { buffer, _ in tap.process(buffer) }
  }

  /// The recognizer reports silence, or a cancel, as an error of the assistant domain.
  private nonisolated static func isBenign(_ error: any Error) -> Bool {
    let error = error as NSError
    return error.domain == "kLSRErrorDomain" && error.code == 301
      || error.domain == "kAFAssistantErrorDomain" && [216, 1110].contains(error.code)
  }

  private nonisolated static func resultHandler(
    _ deliver: @escaping @Sendable (SpeechEvent) -> Void
  ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
    { result, error in
      if let result {
        let text = result.bestTranscription.formattedString
        deliver(result.isFinal ? .final(text) : .partial(text))
      } else if let error {
        deliver(Self.isBenign(error) ? .stopped : .failed)
      }
    }
  }
}

/// Feeds microphone buffers to the recognizer and reports their level, on the audio thread.
private final class MicrophoneTap: @unchecked Sendable {
  private let request: SFSpeechAudioBufferRecognitionRequest
  private let deliver: @Sendable (SpeechEvent) -> Void

  init(
    request: SFSpeechAudioBufferRecognitionRequest,
    deliver: @escaping @Sendable (SpeechEvent) -> Void
  ) {
    self.request = request
    self.deliver = deliver
  }

  func process(_ buffer: AVAudioPCMBuffer) {
    request.append(buffer)
    deliver(.level(Self.level(of: buffer)))
  }

  /// The root mean square of the samples, scaled up because speech is quiet.
  private static func level(of buffer: AVAudioPCMBuffer) -> Float {
    guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
    let count = Int(buffer.frameLength)
    var sum: Float = 0
    for index in 0..<count {
      sum += samples[index] * samples[index]
    }
    return min(1, (sum / Float(count)).squareRoot() * 6)
  }
}

@MainActor
final class LiveSpeechSpeaker: NSObject, SpeechSpeaker, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()
  private var onFinish: (@MainActor () -> Void)?
  /// Tells the end of the utterance spoken now from a late one of an utterance `stop()` cut off.
  private(set) var current: AVSpeechUtterance?

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speak(_ text: String, onFinish: @escaping @MainActor () -> Void) {
    let utterance = AVSpeechUtterance(string: text)
    current = utterance
    self.onFinish = onFinish
    synthesizer.speak(utterance)
  }

  func stop() {
    current = nil
    onFinish = nil
    synthesizer.stopSpeaking(at: .immediate)
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    ended(utterance)
  }

  /// The system cancels speech when another app takes the audio, with no `stop()` of ours.
  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    ended(utterance)
  }

  private nonisolated func ended(_ utterance: AVSpeechUtterance) {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor in
      guard let current, ObjectIdentifier(current) == id else { return }
      let finish = onFinish
      self.current = nil
      onFinish = nil
      finish?()
    }
  }
}
