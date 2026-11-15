import Foundation
import Testing

@testable import AssistantLink

struct CallSheetPresentationTests {
  private let question = TranscriptLine(id: "u-1", text: "What's on today?", isFromUser: true)
  private let answer = TranscriptLine(id: "a-1", text: "Nothing.", isFromUser: false)

  private func sheet(
    _ state: VoiceCall.State = .listening, isMuted: Bool = false, listeningFailed: Bool = false,
    heard: String = "", transcript: [TranscriptLine] = []
  ) -> CallSheetPresentation {
    CallSheetPresentation(
      state: state, isMuted: isMuted, listeningFailed: listeningFailed, heard: heard,
      transcript: transcript)
  }

  @Test func theAssistantSpeakingShowsUnderItsReply() {
    #expect(sheet(.speaking, transcript: [question, answer]).turn == .speaking)
  }

  @Test func wordsBeingHeardShowAsAPartialBubble() {
    let presentation = sheet(heard: "And can you", transcript: [question, answer])

    #expect(presentation.turn == .listening("And can you"))
    #expect(!presentation.isWorking)
  }

  @Test func aSentUtteranceWithoutAReplyShowsTheAssistantWorking() {
    let presentation = sheet(transcript: [answer, question])

    #expect(presentation.turn == .thinking)
    #expect(presentation.isWorking)
  }

  @Test func theAssistantStillWorksWhileTheUserIsMuted() {
    #expect(sheet(isMuted: true, transcript: [question]).turn == .thinking)
  }

  @Test func anAnsweredUtteranceOrAnEmptyCallShowsNothing() {
    #expect(sheet(transcript: [question, answer]).turn == nil)
    #expect(sheet().turn == nil)
    #expect(sheet(heard: "  ").turn == nil)
  }

  @Test func newWordsComeBeforeTheWorkingIndicator() {
    #expect(sheet(heard: "Also", transcript: [question]).turn == .listening("Also"))
  }

  @Test func listeningThatGaveUpOffersARetryExceptWhileSpeaking() {
    #expect(sheet(listeningFailed: true).offersRetry)
    #expect(!sheet(.speaking, listeningFailed: true).offersRetry)
    #expect(!sheet().offersRetry)
  }
}

struct VoiceChatTranscriptTests {
  private func event(
    _ id: String, _ type: Event.Kind = .textMessage, sender: Event.Sender = .assistant,
    at seconds: Double = 0, deleted: Bool = false
  ) -> Event {
    Event(
      id: id, assistantID: "as-1", type: type, sender: sender,
      createdAt: Date(timeIntervalSince1970: 1000 + seconds), deleted: deleted,
      text: type == .textMessage ? id : nil)
  }

  @Test func theMessagesOfAnEndedCallFoldIntoItsEntry() {
    let timeline = Timeline(events: [
      event("m-1", sender: .user), event("s", .callStarted), event("v-1", sender: .user),
      event("r-1"), event("e", .callEnded), event("r-2"),
    ])

    #expect(timeline.rows.map(\.id) == ["m-1", "s", "e", "r-2"])
  }

  @Test func theMessagesOfACallStillRunningShow() {
    let timeline = Timeline(events: [event("s", .callStarted), event("v-1", sender: .user)])

    #expect(timeline.rows.map(\.id) == ["s", "v-1"])
  }

  @Test func theEntryOpensTheCallsMessagesAndDuration() {
    let timeline = Timeline(events: [
      event("r-0"), event("s", .callStarted, at: 0), event("v-1", sender: .user, at: 5),
      event("x", deleted: true), event("r-1", at: 9), event("e", .callEnded, at: 72),
    ])

    let chat = timeline.voiceChat(endedBy: timeline.events[5])

    #expect(chat.id == "e")
    #expect(chat.seconds == 72)
    #expect(chat.startedAt == Date(timeIntervalSince1970: 1000))
    #expect(
      chat.lines == [
        TranscriptLine(id: "v-1", text: "v-1", isFromUser: true),
        TranscriptLine(id: "r-1", text: "r-1", isFromUser: false),
      ])
  }

  @Test func anEndWithoutALoadedStartHasAnEmptyTranscript() {
    let timeline = Timeline(events: [event("r-1"), event("e", .callEnded)])

    #expect(timeline.voiceChat(endedBy: timeline.events[1]).lines.isEmpty)
    #expect(timeline.rows.map(\.id) == ["r-1", "e"])
  }

  @Test(arguments: [(0, "00:00"), (48, "00:48"), (72, "01:12"), (3665, "61:05")])
  func theCallDurationShowsMinutesAndSeconds(seconds: Int, time: String) {
    #expect(VoiceChat.duration(seconds: seconds) == time)
  }
}
