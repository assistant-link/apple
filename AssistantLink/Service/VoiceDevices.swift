import AVFoundation
import OSLog
import Speech

extension VoiceCall {
  static func live(kokoro: KokoroVoice = KokoroVoice()) -> VoiceCall {
    VoiceCall(
      listener: LiveSpeechListener(), speaker: LiveSpeechSpeaker(kokoro: kokoro),
      audio: LiveVoiceAudio())
  }
}

extension Dictation {
  static func live() -> Dictation {
    Dictation(listener: LiveSpeechListener(), audio: LiveVoiceAudio())
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

  private var isSpeakerOn = true

  func activate() throws {
    try setCategory()
    try AVAudioSession.sharedInstance().setActive(true)
  }

  func setSpeaker(_ on: Bool) {
    isSpeakerOn = on
    try? setCategory()
  }

  /// Unlike overriding the output port, `defaultToSpeaker` leaves a connected headset in use.
  private func setCategory() throws {
    var options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP]
    if isSpeakerOn { options.insert(.defaultToSpeaker) }
    try AVAudioSession.sharedInstance().setCategory(
      .playAndRecord, mode: .voiceChat, options: options)
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

/// Recognizes English speech from the microphone with the best recognizer that is ready.
@MainActor
final class LiveSpeechListener: SpeechListener {
  var vocabulary: [String] = []
  private let engine = AVAudioEngine()
  private var session: (any RecognitionSession)?
  /// Tells results of a recognition that was stopped from those of the current one.
  private var generation = 0

  init() {
    if #available(iOS 26, *) { TranscriberModel.shared.prepare() }
  }

  func start(_ handler: @escaping @MainActor (SpeechEvent) -> Void) throws {
    stop()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    // A route still switching reports no sample rate, which `installTap` can't take.
    guard format.sampleRate > 0, let session = makeSession(microphone: format) else {
      throw SpeechListenerError.recognizerUnavailable
    }
    let generation = generation
    let deliver: @Sendable (SpeechEvent) -> Void = { [weak self] event in
      Task { @MainActor in
        guard let self, self.generation == generation else { return }
        handler(event)
      }
    }
    let tap = MicrophoneTap(session: session, deliver: deliver)
    input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.block(of: tap))
    do {
      engine.prepare()
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      session.cancel()
      throw error
    }
    self.session = session
    session.begin(deliver)
  }

  /// SpeechTranscriber from iOS 26 once its model is installed, else SFSpeechRecognizer.
  private func makeSession(microphone: AVAudioFormat) -> (any RecognitionSession)? {
    if #available(iOS 26, *) {
      let model = TranscriberModel.shared
      model.prepare()
      if let ready = model.ready,
        let session = TranscriberSession(ready, microphone: microphone, vocabulary: vocabulary)
      {
        return session
      }
    }
    return RecognizerSession(vocabulary: vocabulary)
  }

  func finish() {
    stopMicrophone()
    session?.finish()
  }

  func stop() {
    generation += 1
    stopMicrophone()
    session?.cancel()
    session = nil
  }

  private func stopMicrophone() {
    engine.stop()
    engine.inputNode.removeTap(onBus: 0)
  }

  // The system calls this from a background queue, so it must not be isolated to the main
  // actor, which closures made in a main actor method would be.
  private nonisolated static func block(
    of tap: MicrophoneTap
  ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
    { buffer, _ in tap.process(buffer) }
  }
}

/// Feeds microphone buffers to the recognizer and reports their level, on the audio thread.
private final class MicrophoneTap: Sendable {
  private let session: any RecognitionSession
  private let deliver: @Sendable (SpeechEvent) -> Void

  init(session: any RecognitionSession, deliver: @escaping @Sendable (SpeechEvent) -> Void) {
    self.session = session
    self.deliver = deliver
  }

  func process(_ buffer: AVAudioPCMBuffer) {
    session.append(buffer)
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

/// What the choice of the voice that reads replies needs to know of an installed voice.
struct ReplyVoice: Equatable {
  enum Quality: Int {
    case standard, enhanced, premium
  }

  let id: String
  let language: String
  let quality: Quality
  let isNovelty: Bool

  /// The best voice that speaks the language of `language`, of any region; a voice of the same
  /// region only wins a tie in quality. Nil when none does, so the system default stays.
  static func best(of voices: [ReplyVoice], language: String) -> ReplyVoice? {
    let code = Self.code(language)
    func rank(_ voice: ReplyVoice) -> Int {
      voice.quality.rawValue * 2 + (voice.language == language ? 1 : 0)
    }
    let spoken = voices.filter { !$0.isNovelty && Self.code($0.language) == code }
    return spoken.max { rank($0) < rank($1) }
  }

  private static func code(_ language: String) -> Substring {
    language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? ""
  }
}

extension ReplyVoice {
  init(_ voice: AVSpeechSynthesisVoice) {
    let quality: Quality =
      switch voice.quality {
      case .premium: .premium
      case .enhanced: .enhanced
      default: .standard
      }
    // A personal voice is the user's own, not one to read replies in.
    let traits = voice.voiceTraits
    let isNovelty = traits.contains(.isNoveltyVoice) || traits.contains(.isPersonalVoice)
    self.init(
      id: voice.identifier, language: voice.language, quality: quality, isNovelty: isNovelty)
  }

  /// The best installed voice for the language of the user, else for US English.
  static func installed() -> AVSpeechSynthesisVoice? {
    let voices = AVSpeechSynthesisVoice.speechVoices()
    let descriptors = voices.map(ReplyVoice.init)
    let languages = [Locale.current.identifier(.bcp47), "en-US"]
    let chosen = languages.lazy.compactMap { best(of: descriptors, language: $0) }.first
    return chosen.flatMap { AVSpeechSynthesisVoice(identifier: $0.id) }
  }
}

@MainActor
final class LiveSpeechSpeaker: NSObject, SpeechSpeaker, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()
  private var engine: (any ReplySpeechEngine)?
  private let chooseEngine: (@MainActor () -> (any ReplySpeechEngine)?)?
  private var onFinish: (@MainActor () -> Void)?
  private lazy var voice: AVSpeechSynthesisVoice? = {
    let voice = ReplyVoice.installed()
    Logger(subsystem: "ai.assistantlink.app", category: "speech")
      .info("Reading replies with \(voice?.name ?? "the system voice", privacy: .public)")
    return voice
  }()
  /// Tells the end of the utterance spoken now from a late one of an utterance `stop()` cut off.
  private(set) var current: AVSpeechUtterance?

  /// With an `engine`, replies are read in its voice once it is ready, and in the best system
  /// voice until then or when it fails.
  init(engine: (any ReplySpeechEngine)?) {
    self.engine = engine
    chooseEngine = nil
    super.init()
    synthesizer.delegate = self
    engine?.prepare()
  }

  /// Asks `kokoro` at the start of each call whether to read replies with it.
  init(kokoro: KokoroVoice = KokoroVoice()) {
    chooseEngine = { kokoro.usedEngine() }
    super.init()
    synthesizer.delegate = self
  }

  func prepareForCall() {
    if let chooseEngine {
      let chosen = chooseEngine()
      if chosen !== engine { engine?.stop() }
      engine = chosen
    }
    engine?.prepare()
  }

  func speak(_ text: String, onFinish: @escaping @MainActor () -> Void) {
    self.onFinish = onFinish
    guard let engine, engine.isReady else {
      engine?.prepare()
      speakWithSystemVoice(text)
      return
    }
    engine.speak(text) { [weak self] result in
      guard let self, self.onFinish != nil else { return }
      switch result {
      case .finished: self.finish()
      case .failed: self.speakWithSystemVoice(text)
      }
    }
  }

  func stop() {
    current = nil
    onFinish = nil
    engine?.stop()
    synthesizer.stopSpeaking(at: .immediate)
  }

  private func speakWithSystemVoice(_ text: String) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    current = utterance
    synthesizer.speak(utterance)
  }

  private func finish() {
    let finish = onFinish
    current = nil
    onFinish = nil
    finish?()
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
      finish()
    }
  }
}
