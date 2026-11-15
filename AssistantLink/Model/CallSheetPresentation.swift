import Foundation

/// One turn of a voice chat, as the call sheet and the transcript sheet show it.
struct TranscriptLine: Equatable, Identifiable, Sendable {
  let id: String
  let text: String
  let isFromUser: Bool
}

/// What the call sheet shows under the transcript.
struct CallSheetPresentation: Equatable {
  enum Turn: Equatable {
    /// Under the Assistant's reply being read out.
    case speaking
    /// The words heard so far, as a partial bubble.
    case listening(String)
    /// From the moment the user's words are sent until a reply comes.
    case thinking
  }

  let phase: CallBannerPhase
  let turn: Turn?

  init(
    state: VoiceCall.State, isMuted: Bool, listeningFailed: Bool, heard: String,
    transcript: [TranscriptLine]
  ) {
    phase = CallBannerPhase(state: state, isMuted: isMuted, listeningFailed: listeningFailed)
    let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
    if state == .speaking {
      turn = .speaking
    } else if !heard.isEmpty {
      turn = .listening(heard)
    } else if transcript.last?.isFromUser == true {
      turn = .thinking
    } else {
      turn = nil
    }
  }

  @MainActor
  init(_ call: VoiceCall) {
    self.init(
      state: call.state, isMuted: call.isMuted, listeningFailed: call.listeningFailed,
      heard: call.heard, transcript: call.transcript)
  }

  var isWorking: Bool { turn == .thinking }

  var offersRetry: Bool { phase == .notListening }
}
