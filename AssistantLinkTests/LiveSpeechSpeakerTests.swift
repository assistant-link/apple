import AVFoundation
import Testing

@testable import AssistantLink

@MainActor
struct LiveSpeechSpeakerTests {
  private func settle() async {
    try? await Task.sleep(for: .milliseconds(50))
  }

  @Test func aCancelledUtteranceFinishesTheSpeech() async throws {
    let speaker = LiveSpeechSpeaker()
    var finishes = 0
    speaker.speak(" ") { finishes += 1 }
    let utterance = try #require(speaker.current)

    speaker.speechSynthesizer(AVSpeechSynthesizer(), didCancel: utterance)
    await settle()

    #expect(finishes == 1)
  }

  @Test func theEndOfAnOtherUtteranceIsIgnored() async {
    let speaker = LiveSpeechSpeaker()
    var finishes = 0
    speaker.speak(" ") { finishes += 1 }

    speaker.speechSynthesizer(AVSpeechSynthesizer(), didCancel: AVSpeechUtterance(string: "old"))
    await settle()

    #expect(finishes == 0)
    speaker.stop()
  }

  @Test func stoppingDoesNotFinishTheSpeech() async throws {
    let speaker = LiveSpeechSpeaker()
    var finishes = 0
    speaker.speak(" ") { finishes += 1 }
    let utterance = try #require(speaker.current)

    speaker.stop()
    speaker.speechSynthesizer(AVSpeechSynthesizer(), didCancel: utterance)
    await settle()

    #expect(finishes == 0)
  }
}
