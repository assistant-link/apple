import AVFoundation
import OSLog
import Speech
import Synchronization

/// The language speech is recognized in. Users dictate in English whatever the language of the
/// phone, and a recognizer of another language turns English into garbled words.
enum SpeechLocale {
  static let fallback = "en-US"

  /// The first of the user's preferred languages that is English of a region `isSupported`, else
  /// US English.
  static func english(preferredLanguages: [String], isSupported: (String) -> Bool) -> String {
    let english = preferredLanguages.lazy.map { Locale(identifier: $0) }
      .filter { $0.language.languageCode == .english && $0.region != nil }
      .map { $0.identifier(.bcp47) }
    return english.first(where: isSupported) ?? fallback
  }
}

/// The text of a SpeechTranscriber recognition so far: its finalized results in order, then the
/// latest volatile one, which the next result replaces.
struct TranscriptionText {
  private(set) var finalized = ""
  private var volatile = ""

  var text: String { SpeechSegments.join(finalized, volatile) }

  mutating func add(_ result: String, isFinal: Bool) {
    if isFinal {
      finalized = SpeechSegments.join(finalized, result)
      volatile = ""
    } else {
      volatile = result
    }
  }
}

/// One recognition of the microphone's audio.
protocol RecognitionSession: AnyObject, Sendable {
  /// Called on the audio thread.
  func append(_ buffer: AVAudioPCMBuffer)
  func begin(_ deliver: @escaping @Sendable (SpeechEvent) -> Void)
  /// Ends the audio; the final result still comes.
  func finish()
  func cancel()
}

/// SFSpeechRecognizer, for systems before iOS 26 and until the SpeechTranscriber model is
/// installed.
final class RecognizerSession: RecognitionSession, @unchecked Sendable {
  private static let locale: Locale = {
    let supported = Set(SFSpeechRecognizer.supportedLocales().map { $0.identifier(.bcp47) })
    return Locale(
      identifier: SpeechLocale.english(
        preferredLanguages: Locale.preferredLanguages, isSupported: supported.contains))
  }()

  private let recognizer: SFSpeechRecognizer
  private let request = SFSpeechAudioBufferRecognitionRequest()
  /// Only used on the main actor.
  private var task: SFSpeechRecognitionTask?

  init?(vocabulary: [String]) {
    guard let recognizer = SFSpeechRecognizer(locale: Self.locale), recognizer.isAvailable else {
      return nil
    }
    self.recognizer = recognizer
    Self.configure(request, vocabulary: vocabulary)
  }

  /// Apple's server recognition hears better than the on-device model, so it is not ruled out.
  static func configure(_ request: SFSpeechAudioBufferRecognitionRequest, vocabulary: [String]) {
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = false
    request.addsPunctuation = true
    request.taskHint = .dictation
    request.contextualStrings = vocabulary
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    request.append(buffer)
  }

  func begin(_ deliver: @escaping @Sendable (SpeechEvent) -> Void) {
    task = recognizer.recognitionTask(with: request) { result, error in
      if let result {
        let text = result.bestTranscription.formattedString
        deliver(result.isFinal ? .final(text) : .partial(text))
      } else if let error {
        deliver(Self.isBenign(error) ? .stopped : .failed)
      }
    }
  }

  func finish() {
    request.endAudio()
  }

  func cancel() {
    request.endAudio()
    task?.cancel()
  }

  /// The recognizer reports silence, or a cancel, as an error of the assistant domain.
  private static func isBenign(_ error: any Error) -> Bool {
    let error = error as NSError
    return error.domain == "kLSRErrorDomain" && error.code == 301
      || error.domain == "kAFAssistantErrorDomain" && [216, 1110].contains(error.code)
  }
}

/// Installs the SpeechTranscriber model of the language speech is recognized in, in the
/// background, so that recognitions use it once it is there.
@available(iOS 26, *)
@MainActor
final class TranscriberModel {
  /// `AVAudioFormat` is immutable.
  struct Ready: @unchecked Sendable {
    let locale: Locale
    let format: AVAudioFormat
  }

  static let shared = TranscriberModel()
  private nonisolated static let logger = Logger(
    subsystem: "ai.assistantlink.app", category: "speech")

  private(set) var ready: Ready?
  private var isPreparing = false
  /// A recognition with the model failed, so the rest of this run does without it.
  private var hasFailed = false

  /// Starts installing the model unless it is installed or installing; a failed download is
  /// tried again on the next call.
  func prepare() {
    guard ready == nil, !isPreparing, !hasFailed, SpeechTranscriber.isAvailable else { return }
    isPreparing = true
    Task {
      ready = await Self.install()
      isPreparing = false
    }
  }

  func failed() {
    Self.logger.error("SpeechTranscriber failed; recognizing with SFSpeechRecognizer from now on")
    hasFailed = true
    ready = nil
  }

  nonisolated static func transcriber(locale: Locale) -> SpeechTranscriber {
    SpeechTranscriber(
      locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults],
      attributeOptions: [])
  }

  private nonisolated static func install() async -> Ready? {
    let locales = await SpeechTranscriber.supportedLocales
    let supported = Set(locales.map { $0.identifier(.bcp47) })
    let identifier = SpeechLocale.english(
      preferredLanguages: Locale.preferredLanguages, isSupported: supported.contains)
    guard supported.contains(identifier) else { return nil }
    let locale = Locale(identifier: identifier)
    let modules: [any SpeechModule] = [transcriber(locale: locale)]
    do {
      try await AssetInventory.assetInstallationRequest(supporting: modules)?.downloadAndInstall()
    } catch {
      let reason = error.localizedDescription
      logger.error("SpeechTranscriber model not installed: \(reason, privacy: .public)")
      return nil
    }
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
    else { return nil }
    logger.info("Recognizing speech with SpeechTranscriber in \(identifier, privacy: .public)")
    return Ready(locale: locale, format: format)
  }
}

/// SpeechTranscriber, which hears far better than SFSpeechRecognizer and has no time limit. It
/// never ends a recognition on its own, so only `finish()` brings the final result.
@available(iOS 26, *)
final class TranscriberSession: RecognitionSession, @unchecked Sendable {
  private let transcriber: SpeechTranscriber
  private let analyzer: SpeechAnalyzer
  private let format: AVAudioFormat
  /// Nil when the microphone already gives the format of the model. Only used on the audio thread.
  private let converter: AVAudioConverter?
  private let inputs: AsyncStream<AnalyzerInput>
  private let input: AsyncStream<AnalyzerInput>.Continuation
  private let vocabulary: [String]
  private let isCancelled = Atomic(false)

  init?(_ model: TranscriberModel.Ready, microphone: AVAudioFormat, vocabulary: [String]) {
    if microphone == model.format {
      converter = nil
    } else {
      guard let converter = AVAudioConverter(from: microphone, to: model.format) else { return nil }
      self.converter = converter
    }
    let transcriber = TranscriberModel.transcriber(locale: model.locale)
    self.transcriber = transcriber
    analyzer = SpeechAnalyzer(
      modules: [transcriber],
      options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering))
    format = model.format
    let stream = AsyncStream<AnalyzerInput>.makeStream()
    inputs = stream.stream
    input = stream.continuation
    self.vocabulary = vocabulary
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    guard let converted = convert(buffer) else { return }
    input.yield(AnalyzerInput(buffer: converted))
  }

  func begin(_ deliver: @escaping @Sendable (SpeechEvent) -> Void) {
    Task {
      do {
        let context = AnalysisContext()
        context.contextualStrings[.general] = vocabulary
        // Only DictationTranscriber documents using contextual strings, so they are a mere hint.
        try? await analyzer.setContext(context)
        try await analyzer.start(inputSequence: inputs)
        var text = TranscriptionText()
        for try await result in transcriber.results {
          text.add(String(result.text.characters), isFinal: result.isFinal)
          deliver(.partial(text.text))
        }
        deliver(.final(text.finalized))
      } catch {
        guard !isCancelled.load(ordering: .relaxed) else { return }
        await TranscriberModel.shared.failed()
        deliver(.failed)
      }
    }
  }

  func finish() {
    input.finish()
    Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
  }

  func cancel() {
    isCancelled.store(true, ordering: .relaxed)
    input.finish()
    Task { await analyzer.cancelAndFinishNow() }
  }

  /// The analyzer only takes the format of its model.
  private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let converter else { return buffer }
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
    guard capacity > 0, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
    else { return nil }
    let pending = PendingBuffer(buffer)
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, inputStatus in
      guard let buffer = pending.take() else {
        inputStatus.pointee = .noDataNow
        return nil
      }
      inputStatus.pointee = .haveData
      return buffer
    }
    return status == .error || output.frameLength == 0 ? nil : output
  }
}

/// Hands the converter one buffer, once.
private final class PendingBuffer: @unchecked Sendable {
  private var buffer: AVAudioPCMBuffer?

  init(_ buffer: AVAudioPCMBuffer) {
    self.buffer = buffer
  }

  func take() -> AVAudioPCMBuffer? {
    defer { buffer = nil }
    return buffer
  }
}
