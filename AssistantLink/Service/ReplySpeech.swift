import Foundation
import OSLog
import Observation

enum ReplySpeechResult {
  case finished
  /// Nothing was spoken, so the caller can read the reply another way.
  case failed
}

/// How far a reply voice is from speaking.
enum ReplyVoiceStatus: Equatable, Sendable {
  case notStarted
  /// `fraction`, 0 to 1, is nil until the download reports one.
  case downloading(fraction: Double?)
  /// Loading the model, or compiling it for the device the first time.
  case preparing
  case ready
  /// The last preparation or reply failed; the next `prepare()` tries again.
  case failed
}

/// Speaks a reply in a voice other than the system's; `LiveSpeechSpeaker` falls back to the
/// system voice while it is not ready.
@MainActor
protocol ReplySpeechEngine: AnyObject {
  var status: ReplyVoiceStatus { get }
  /// Gets the engine ready, such as by downloading its model; does nothing when it already is or
  /// is on its way.
  func prepare()
  /// Never calls `onEnd` after `stop()` or another `speak`.
  func speak(_ text: String, onEnd: @escaping @MainActor (ReplySpeechResult) -> Void)
  func stop()
}

extension ReplySpeechEngine {
  var isReady: Bool { status == .ready }
}

struct SpeechClip: Sendable {
  let samples: [Float]
  let sampleRate: Double
}

protocol SentenceSynthesizing: Sendable {
  /// Reports only `downloading` and `preparing`, from any thread.
  func prepare(progress: @escaping @Sendable (ReplyVoiceStatus) -> Void) async throws
  func synthesize(_ sentence: String) async throws -> SpeechClip
}

@MainActor
protocol SamplePlaying: AnyObject {
  /// Plays the clip after those queued before it.
  func enqueue(_ clip: SpeechClip) throws
  /// Calls `handler` when everything queued has been played, unless `stop()` comes first.
  func whenDrained(_ handler: @escaping @MainActor () -> Void)
  func stop()
}

enum SentenceSplitter {
  static func sentences(in text: String) -> [String] {
    var sentences: [String] = []
    text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
      let trimmed = sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !trimmed.isEmpty { sentences.append(trimmed) }
    }
    return sentences
  }
}

/// Synthesizes a reply sentence by sentence, and plays each as soon as it is ready, so the
/// first words come before the end of a long reply is synthesized.
@MainActor
@Observable
final class NeuralReplyEngine: ReplySpeechEngine {
  private let synthesizer: any SentenceSynthesizing
  private let player: any SamplePlaying
  private let logger = Logger(subsystem: "ai.assistantlink.app", category: "speech")
  private(set) var status = ReplyVoiceStatus.notStarted
  @ObservationIgnored private var preparing: Task<Void, Never>?
  @ObservationIgnored private var speaking: Task<Void, Never>?

  init(synthesizer: any SentenceSynthesizing, player: any SamplePlaying) {
    self.synthesizer = synthesizer
    self.player = player
  }

  func prepare() {
    guard !isReady, preparing == nil else { return }
    status = .preparing
    // A stream keeps the reports in order, which a task per report from the downloader's
    // threads would not.
    let (reports, reporter) = AsyncStream.makeStream(
      of: ReplyVoiceStatus.self, bufferingPolicy: .bufferingNewest(1))
    preparing = Task {
      let following = Task {
        for await report in reports { status = report }
      }
      let outcome: ReplyVoiceStatus
      do {
        try await synthesizer.prepare { reporter.yield($0) }
        outcome = .ready
        logger.info("The neural voice is ready")
      } catch {
        outcome = .failed
        let reason = error.localizedDescription
        logger.error("The neural voice is not available: \(reason, privacy: .public)")
      }
      reporter.finish()
      await following.value
      status = outcome
      preparing = nil
    }
  }

  func speak(_ text: String, onEnd: @escaping @MainActor (ReplySpeechResult) -> Void) {
    stop()
    let sentences = SentenceSplitter.sentences(in: text)
    guard !sentences.isEmpty else {
      onEnd(.finished)
      return
    }
    speaking = Task {
      var played = 0
      for sentence in sentences {
        do {
          let clip = try await synthesizer.synthesize(sentence)
          try Task.checkCancellation()
          try player.enqueue(clip)
          played += 1
        } catch {
          if Task.isCancelled { return }
          let reason = error.localizedDescription
          logger.error("Could not speak a sentence: \(reason, privacy: .public)")
          if played == 0 {
            status = .failed
            onEnd(.failed)
            return
          }
        }
      }
      player.whenDrained { onEnd(.finished) }
    }
  }

  func stop() {
    speaking?.cancel()
    speaking = nil
    player.stop()
  }
}
