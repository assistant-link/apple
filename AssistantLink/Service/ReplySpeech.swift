import Foundation
import OSLog

enum ReplySpeechResult {
  case finished
  /// Nothing was spoken, so the caller can read the reply another way.
  case failed
}

/// Speaks a reply in a voice other than the system's; `LiveSpeechSpeaker` falls back to the
/// system voice while it is not ready.
@MainActor
protocol ReplySpeechEngine: AnyObject {
  var isReady: Bool { get }
  /// Gets the engine ready, such as by downloading its model; does nothing when it already is.
  func prepare()
  /// Never calls `onEnd` after `stop()` or another `speak`.
  func speak(_ text: String, onEnd: @escaping @MainActor (ReplySpeechResult) -> Void)
  func stop()
}

struct SpeechClip: Sendable {
  let samples: [Float]
  let sampleRate: Double
}

protocol SentenceSynthesizing: Sendable {
  func prepare() async throws
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
final class NeuralReplyEngine: ReplySpeechEngine {
  private let synthesizer: any SentenceSynthesizing
  private let player: any SamplePlaying
  private let logger = Logger(subsystem: "ai.assistantlink.app", category: "speech")
  private(set) var isReady = false
  private var preparing: Task<Void, Never>?
  private var speaking: Task<Void, Never>?

  init(synthesizer: any SentenceSynthesizing, player: any SamplePlaying) {
    self.synthesizer = synthesizer
    self.player = player
  }

  func prepare() {
    guard !isReady, preparing == nil else { return }
    preparing = Task {
      do {
        try await synthesizer.prepare()
        isReady = true
        logger.info("The neural voice is ready")
      } catch {
        let reason = error.localizedDescription
        logger.error("The neural voice is not available: \(reason, privacy: .public)")
      }
      preparing = nil
    }
  }

  func speak(_ text: String, onEnd: @escaping @MainActor (ReplySpeechResult) -> Void) {
    stop()
    let sentences = SentenceSplitter.sentences(in: text)
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
            isReady = false
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
