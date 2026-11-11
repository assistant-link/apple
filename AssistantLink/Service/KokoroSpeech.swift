import AVFoundation
import FluidAudio

extension LiveSpeechSpeaker {
  /// Kokoro speaks English only here, so other languages stay with the system voice.
  static func live() -> LiveSpeechSpeaker {
    let isEnglish = Locale.current.language.languageCode == .english
    return LiveSpeechSpeaker(engine: isEnglish ? NeuralReplyEngine.kokoro() : nil)
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

  func prepare() async throws {
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
