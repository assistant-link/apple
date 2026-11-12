import AVFoundation
import FluidAudio
import Observation

/// The reply voice the user picks in Settings > Assistant Link. The raw values are those of
/// `Settings.bundle`.
enum ReplyVoiceChoice: String {
  case apple
  case kokoro

  static let key = "replyVoice"

  /// Registered rather than written, so a choice the user made stays theirs.
  static func registerDefaults(in defaults: UserDefaults = .standard) {
    defaults.register(defaults: [key: kokoro.rawValue])
  }

  /// A value this version does not know, such as one a later version wrote, means the default.
  static func current(defaults: UserDefaults = .standard) -> ReplyVoiceChoice {
    defaults.string(forKey: key).flatMap(ReplyVoiceChoice.init(rawValue:)) ?? .kokoro
  }
}

/// The one Kokoro engine of the app. Where Core ML runs safely it starts getting ready as the app
/// opens, so the model has downloaded by the time a call needs it, and the calls speak with that
/// same engine. Elsewhere only a call makes and prepares it.
@MainActor
@Observable
final class KokoroVoice {
  private let defaults: UserDefaults
  private let isEnglish: Bool
  private let runsSafely: Bool
  private let make: @MainActor () -> any ReplySpeechEngine
  private var engine: (any ReplySpeechEngine)?

  /// Where Core ML crashes, no `catch` survives it, so opening the app leaves Kokoro alone there:
  /// only a call with Kokoro as the reply voice takes that risk, as the Settings footer warns.
  init(
    defaults: UserDefaults = .standard,
    isEnglish: Bool = Locale.current.language.languageCode == .english,
    runsSafely: Bool = KokoroSynthesizer.runsSafely(
      on: ProcessInfo.processInfo.operatingSystemVersion),
    make: @escaping @MainActor () -> any ReplySpeechEngine = { NeuralReplyEngine.kokoro() }
  ) {
    self.defaults = defaults
    self.isEnglish = isEnglish
    self.runsSafely = runsSafely
    self.make = make
  }

  /// Read again each time, so a change in Settings applies to the next call. Kokoro speaks
  /// English only here, so other languages stay with the system voice.
  var isUsed: Bool {
    isEnglish && ReplyVoiceChoice.current(defaults: defaults) == .kokoro
  }

  /// Nil when the replies are not read with Kokoro.
  var status: ReplyVoiceStatus? {
    guard isUsed else { return nil }
    return engine?.status ?? .notStarted
  }

  /// Made on first use and kept, as it holds the loaded model.
  func usedEngine() -> (any ReplySpeechEngine)? {
    guard isUsed else { return nil }
    if engine == nil { engine = make() }
    return engine
  }

  /// Called as the app opens or becomes active. Starts the download on any network, or picks it
  /// up again after a failure, such as one the app's suspension caused. Does nothing while it is
  /// on its way, once Kokoro is ready, or where Core ML crashes, even after a call made Kokoro.
  func prepare() {
    guard runsSafely else { return }
    usedEngine()?.prepare()
  }

  /// Asked for during a call, so it prepares Kokoro where `prepare()` does not.
  func retry() {
    usedEngine()?.prepare()
  }
}

extension NeuralReplyEngine {
  static func kokoro() -> NeuralReplyEngine {
    NeuralReplyEngine(synthesizer: KokoroSynthesizer(), player: EnginePlayer())
  }
}

/// Kokoro-82M on Core ML. The first `prepare()` downloads the model, at most about 280 MB, and
/// compiles it for the device; later ones only load it.
struct KokoroSynthesizer: SentenceSynthesizing {
  static let voice = "af_heart"

  private let manager = KokoroAneManager(defaultVoice: Self.voice)

  /// Core ML segfaults in Apple's libBNNS from iOS 26.4 on (FluidAudio#844, #889). No `catch`
  /// survives it, it ends the call, and no compute-unit choice avoids it (FluidAudio#587, #817).
  /// `KokoroVoice` does not prepare Kokoro there as the app opens, only for a call.
  static func runsSafely(on system: OperatingSystemVersion) -> Bool {
    system.majorVersion < 26 || (system.majorVersion == 26 && system.minorVersion < 4)
  }

  /// FluidAudio downloads on its own default session, which allows these.
  static var downloadsOnAnyNetwork: Bool {
    let configuration = ModelHub.session.configuration
    return configuration.allowsCellularAccess && configuration.allowsExpensiveNetworkAccess
  }

  /// `ModelHub.download` reports the download over the first half of the fraction and keeps the
  /// rest for compiling, which `ensureModels` does not do (FluidAudio 0.18.3).
  static func downloadFraction(reported: Double) -> Double {
    min(max(reported / 0.5, 0), 1)
  }

  /// Downloads first, as `initialize()` takes no progress handler; it then finds the files in
  /// place. Files already downloaded are kept, so an interrupted download resumes.
  func prepare(progress: @escaping @Sendable (ReplyVoiceStatus) -> Void) async throws {
    try await KokoroAneResourceDownloader.ensureModels(progressHandler: { report in
      if case .listing = report.phase {
        progress(.downloading(fraction: nil))
      } else if case .downloading = report.phase {
        let fraction = Self.downloadFraction(reported: report.fractionCompleted)
        progress(.downloading(fraction: fraction))
      }
    })
    progress(.preparing)
    try await manager.initialize()
  }

  func synthesize(_ sentence: String) async throws -> SpeechClip {
    let result = try await manager.synthesizeDetailed(text: sentence, voice: Self.voice)
    return SpeechClip(samples: result.samples, sampleRate: Double(result.sampleRate))
  }
}

enum EnginePlayerError: Error {
  case noBuffer
}

/// Plays the clips back to back on the audio session the call set up.
@MainActor
final class EnginePlayer: SamplePlaying {
  private let engine = AVAudioEngine()
  private let node = AVAudioPlayerNode()
  private var connectedFormat: AVAudioFormat?
  private var pending = 0
  private var drained: (@MainActor () -> Void)?
  /// Tells the completion of a buffer `stop()` cut off from one still to be played.
  private var generation = 0

  init() {
    engine.attach(node)
  }

  func enqueue(_ clip: SpeechClip) throws {
    guard
      let format = AVAudioFormat(standardFormatWithSampleRate: clip.sampleRate, channels: 1),
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(clip.samples.count)),
      let channel = buffer.floatChannelData?[0]
    else { throw EnginePlayerError.noBuffer }
    buffer.frameLength = buffer.frameCapacity
    clip.samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }

    if connectedFormat != format {
      engine.stop()
      engine.connect(node, to: engine.mainMixerNode, format: format)
      connectedFormat = format
    }
    if !engine.isRunning { try engine.start() }
    pending += 1
    let generation = generation
    node.scheduleBuffer(
      buffer, completionCallbackType: .dataPlayedBack,
      completionHandler: Self.completion { [weak self] in
        Task { @MainActor in self?.played(generation) }
      })
    node.play()
  }

  func whenDrained(_ handler: @escaping @MainActor () -> Void) {
    if pending == 0 { handler() } else { drained = handler }
  }

  func stop() {
    generation += 1
    pending = 0
    drained = nil
    node.stop()
    engine.stop()
  }

  private func played(_ generation: Int) {
    guard generation == self.generation else { return }
    pending -= 1
    guard pending == 0, let handler = drained else { return }
    drained = nil
    handler()
  }

  // The system calls the handler from an audio thread, so it must not be isolated to the main
  // actor, which a closure made in a main actor method would be.
  private nonisolated static func completion(
    _ done: @escaping @Sendable () -> Void
  ) -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
    { _ in done() }
  }
}
