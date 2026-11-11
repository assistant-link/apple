import AVFoundation
import SherpaOnnx

extension LiveSpeechSpeaker {
  static func live() -> LiveSpeechSpeaker {
    let language = Locale.current.language.languageCode
    return LiveSpeechSpeaker(engine: usesKokoro(language: language) ? .kokoro() : nil)
  }

  /// Kokoro speaks English only here, so other languages stay with the system voice.
  static func usesKokoro(language: Locale.LanguageCode?) -> Bool {
    language == .english
  }
}

extension NeuralReplyEngine {
  static func kokoro() -> NeuralReplyEngine {
    NeuralReplyEngine(synthesizer: KokoroSynthesizer(), player: EnginePlayer())
  }
}

/// Downloads the Kokoro model on first use, about 150 MB, and keeps it in Application Support.
struct KokoroModelStore: Sendable {
  struct File: Sendable {
    let name: String
    let size: Int
  }

  /// The int8 build of Kokoro-82M v1.0 in sherpa-onnx's format, pinned to a commit.
  static let revision = "57adb37fc0e8d4bd430cfc1b8f8c2294945b9af2"
  static let files = [
    File(name: "model.int8.onnx", size: 114_202_993),
    File(name: "voices.bin", size: 28_200_960),
    File(name: "tokens.txt", size: 687),
    File(name: "lexicon-us-en.txt", size: 5_956_885),
  ]

  struct SizeMismatch: Error {}

  let root: URL
  let session: URLSession
  let files: [File]

  init(
    root: URL = URL.applicationSupportDirectory.appending(path: "Kokoro"),
    session: URLSession = .shared, files: [File] = Self.files
  ) {
    self.root = root
    self.session = session
    self.files = files
  }

  /// Returns the folder with the model files, downloading them if they are not there yet.
  func prepare() async throws -> URL {
    let manager = FileManager.default
    let folder = root.appending(path: Self.revision)
    if manager.fileExists(atPath: folder.path) { return folder }

    let partial = root.appending(path: "\(Self.revision).partial")
    try? manager.removeItem(at: partial)
    try manager.createDirectory(at: partial, withIntermediateDirectories: true)
    do {
      for file in files {
        try await download(file, to: partial.appending(path: file.name))
      }
      try manager.moveItem(at: partial, to: folder)
    } catch {
      try? manager.removeItem(at: partial)
      throw error
    }
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var excluded = root
    try? excluded.setResourceValues(values)
    return folder
  }

  private func download(_ file: File, to destination: URL) async throws {
    let url = URL(
      string: "https://huggingface.co/csukuangfj/kokoro-int8-multi-lang-v1_0/resolve/"
        + "\(Self.revision)/\(file.name)")!
    let (temporary, response) = try await session.download(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize
    guard size == file.size else { throw SizeMismatch() }
    try FileManager.default.moveItem(at: temporary, to: destination)
  }
}

/// Kokoro-82M on ONNX Runtime through sherpa-onnx. The session is created on first use and
/// released after a while without speech, because it holds about 150 MB.
actor KokoroSynthesizer: SentenceSynthesizing {
  /// Never `coreml`: Core ML segfaults in Apple's libBNNS from iOS 26.4 on (FluidAudio#844,
  /// #889), and no `catch` survives it.
  static let provider = "cpu"
  /// `af_heart` in the multi-lang v1.0 voice table.
  static let speakerID = 3
  private static let idleTimeout = Duration.seconds(120)

  private let store: KokoroModelStore
  private var tts: SherpaOnnxOfflineTtsWrapper?
  private var unloading: Task<Void, Never>?

  init(store: KokoroModelStore = KokoroModelStore()) {
    self.store = store
  }

  func prepare() async throws {
    _ = try await loaded()
    scheduleUnload()
  }

  func synthesize(_ sentence: String) async throws -> SpeechClip {
    let tts = try await loaded()
    unloading?.cancel()
    let audio = tts.generate(text: sentence, sid: Self.speakerID, speed: 1.0)
    scheduleUnload()
    let samples = audio.samples
    guard !samples.isEmpty else { throw SynthesisError.noAudio }
    return SpeechClip(samples: samples, sampleRate: Double(audio.sampleRate))
  }

  private enum SynthesisError: Error {
    case cannotLoad
    case noAudio
  }

  private func loaded() async throws -> SherpaOnnxOfflineTtsWrapper {
    unloading?.cancel()
    if let tts { return tts }
    let folder = try await store.prepare()
    // Another call may have loaded it while the files were being downloaded.
    if let tts { return tts }
    let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
      model: folder.appending(path: "model.int8.onnx").path,
      voices: folder.appending(path: "voices.bin").path,
      tokens: folder.appending(path: "tokens.txt").path,
      lexicon: folder.appending(path: "lexicon-us-en.txt").path)
    let model = sherpaOnnxOfflineTtsModelConfig(
      kokoro: kokoro, numThreads: 2, provider: Self.provider)
    var config = sherpaOnnxOfflineTtsConfig(model: model)
    let created = SherpaOnnxOfflineTtsWrapper(config: &config)
    guard created.tts != nil else { throw SynthesisError.cannotLoad }
    tts = created
    return created
  }

  private func scheduleUnload() {
    unloading?.cancel()
    unloading = Task {
      try? await Task.sleep(for: Self.idleTimeout)
      guard !Task.isCancelled else { return }
      tts = nil
    }
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
