import Foundation
import Testing

@testable import AssistantLink

struct VoiceCallEventDecodingTests {
  @Test func decodesAnEndedVoiceCallAndIgnoresUnknownFields() throws {
    let json = Data(
      #"""
      {"id": "e-1", "assistant_id": "as-1", "type": "voice_call", "sender": "user",
       "link_id": null, "created_at": "2026-11-25T10:00:00Z", "deleted": false,
       "future_field": {"nested": true},
       "voice_call": {"call_id": "c-1", "mode": "realtime_relay",
                      "started_at": "2026-11-25T10:00:00Z", "ended_at": "2026-11-25T10:01:12Z",
                      "duration_seconds": 72, "transcript_url": "https://service.test/t/c-1",
                      "ended_by": "user", "voice": {"name": "new"}}}
      """#.utf8)

    let event = try APIClient.decoder.decode(Event.self, from: json)

    #expect(event.type == .voiceCall)
    #expect(event.text == nil)
    let call = try #require(event.voiceCall)
    #expect(call.callID == "c-1")
    #expect(call.mode == "realtime_relay")
    #expect(call.startedAt == Date(timeIntervalSince1970: 1_795_600_800))
    #expect(call.endedAt == Date(timeIntervalSince1970: 1_795_600_872))
    #expect(call.seconds == 72)
    #expect(call.transcriptURL == URL(string: "https://service.test/t/c-1"))
  }

  @Test func aVoiceCallStillOnHasNoEndOrDuration() throws {
    let json = Data(
      #"""
      {"id": "e-1", "assistant_id": "as-1", "type": "voice_call", "sender": "user",
       "created_at": "2026-11-25T10:00:00Z",
       "voice_call": {"call_id": "c-1", "mode": "realtime_relay",
                      "started_at": "2026-11-25T10:00:00Z", "ended_at": null,
                      "duration_seconds": null}}
      """#.utf8)

    let call = try #require(try APIClient.decoder.decode(Event.self, from: json).voiceCall)

    #expect(call.endedAt == nil)
    #expect(call.seconds == nil)
    #expect(call.transcriptURL == nil)
  }

  @Test func aVoiceCallWithoutADurationTakesItFromItsTimes() {
    let call = VoiceCallDetails(
      callID: "c-1", startedAt: Date(timeIntervalSince1970: 0),
      endedAt: Date(timeIntervalSince1970: 54))

    #expect(call.seconds == 54)
  }

  @Test func aPayloadThisAppCannotReadKeepsTheEvent() throws {
    let json = Data(
      #"""
      {"id": "e-1", "assistant_id": "as-1", "type": "voice_call", "sender": "user",
       "created_at": "2026-11-25T10:00:00Z", "voice_call": {"mode": 3}}
      """#.utf8)

    let event = try APIClient.decoder.decode(Event.self, from: json)

    #expect(event.type == .voiceCall)
    #expect(event.voiceCall == nil)
  }

  @Test func theListShowsAVoiceCallAsAVoiceChat() {
    let event = Event(
      id: "e-1", assistantID: "as-1", type: .voiceCall, sender: .user, createdAt: .now)

    #expect(ListPreview(event: event, failedMessage: nil).text == "Voice chat")
  }
}

struct TranscriptEntryLiveMessageTests {
  @Test func decodesATranscriptEntryAndIgnoresUnknownFields() {
    let message = LiveMessage(
      text: #"""
        {"jsonrpc": "2.0", "method": "call.transcript_entry",
         "params": {"id": "t-1", "call_id": "c-1", "seq": 2, "speaker": "assistant",
                    "text": "Done.", "started_at": "2026-11-25T10:00:05Z", "ended_at": null,
                    "confidence": 0.9}}
        """#)

    #expect(
      message
        == .transcriptEntry(
          CallTranscriptEntry(
            id: "t-1", callID: "c-1", seq: 2, speaker: .assistant, text: "Done.",
            startedAt: Date(timeIntervalSince1970: 1_795_600_805))))
  }

  @Test func decodesATranscriptEntryUnderItsName() {
    let message = LiveMessage(
      text: #"""
        {"jsonrpc": "2.0", "method": "call.transcript_entry",
         "params": {"transcript_entry": {"id": "t-1", "call_id": "c-1", "seq": 1,
                    "speaker": "user", "text": "Hi", "started_at": "2026-11-25T10:00:00Z",
                    "ended_at": "2026-11-25T10:00:02Z"}}}
        """#)

    guard case .transcriptEntry(let entry) = message else {
      Issue.record("expected call.transcript_entry, got \(message)")
      return
    }
    #expect(entry.speaker == .user)
    #expect(entry.endedAt == Date(timeIntervalSince1970: 1_795_600_802))
  }

  @Test func anEntryWithoutItsFieldsIsIgnored() {
    let message = LiveMessage(
      text: #"{"jsonrpc": "2.0", "method": "call.transcript_entry", "params": {"id": "t-1"}}"#)

    #expect(message == .ignored)
  }
}

struct VoiceCallTimelineTests {
  private func event(
    _ id: String, _ type: Event.Kind = .textMessage, sender: Event.Sender = .assistant,
    at seconds: TimeInterval = 0, call: VoiceCallDetails? = nil
  ) -> Event {
    var event = Event(
      id: id, assistantID: "as-1", type: type, sender: sender,
      createdAt: Date(timeIntervalSince1970: 1000 + seconds),
      text: type == .textMessage ? id : nil)
    event.voiceCall = call
    return event
  }

  private func voiceCall(_ id: String = "v", at seconds: TimeInterval = 0, endedAfter: Int?)
    -> Event
  {
    let start = Date(timeIntervalSince1970: 1000 + seconds)
    return event(
      id, .voiceCall, sender: .user, at: seconds,
      call: VoiceCallDetails(
        callID: "c-\(id)", startedAt: start,
        endedAt: endedAfter.map { start.addingTimeInterval(TimeInterval($0)) },
        durationSeconds: endedAfter))
  }

  @Test func anEndedCallIsOneEntryAndItsRepliesStayOutOfTheChat() {
    let timeline = Timeline(events: [
      event("before", sender: .user), voiceCall(at: 10, endedAfter: 72),
      event("s", .callStarted, sender: .user, at: 10), event("r-1", at: 20),
      event("e", .callEnded, sender: .user, at: 82), event("after", at: 90),
    ])

    #expect(timeline.rows().map(\.id) == ["before", "v", "s", "after"])
    #expect(timeline.liveVoiceCallID(isInCall: false) == nil)
    let chat = timeline.voiceChat(of: timeline.events[1])
    #expect(chat.id == "v")
    #expect(chat.callID == "c-v")
    #expect(chat.seconds == 72)
    #expect(chat.startedAt == Date(timeIntervalSince1970: 1010))
    #expect(chat.lines.isEmpty)
  }

  @Test func aMessageTypedDuringTheCallWithoutAnEntryIsInItsTranscript() {
    let timeline = Timeline(events: [
      voiceCall(at: 10, endedAfter: 72), event("r-1", at: 20),
      event("typed", sender: .user, at: 30), event("e", .callEnded, sender: .user, at: 82),
    ])
    let entries = [
      CallTranscriptEntry(
        id: "t-2", callID: "c-v", seq: 2, speaker: .assistant, text: "r-1",
        startedAt: Date(timeIntervalSince1970: 1019)),
      CallTranscriptEntry(
        id: "t-1", callID: "c-v", seq: 1, speaker: .user, text: "Hi",
        startedAt: Date(timeIntervalSince1970: 1015)),
    ]

    #expect(timeline.rows().map(\.id) == ["v"])
    let chat = timeline.voiceChat(of: timeline.events[0])
    #expect(chat.transcript(of: entries).map(\.id) == ["t-1", "t-2", "typed"])
  }

  @Test func anUnsavedReplyKeepsItsPlaceAmongTheEntries() {
    let timeline = Timeline(events: [
      voiceCall(at: 10, endedAfter: 72), event("unsaved", at: 12),
    ])
    let entries = [
      CallTranscriptEntry(
        id: "t-1", callID: "c-v", seq: 1, speaker: .user, text: "Hi",
        startedAt: Date(timeIntervalSince1970: 1015))
    ]

    let chat = timeline.voiceChat(of: timeline.events[0])
    #expect(chat.transcript(of: entries).map(\.id) == ["unsaved", "t-1"])
    #expect(chat.transcript(of: []).map(\.id) == ["unsaved"])
  }

  @Test func theCallsOwnStartBeforeItsEntryIsNotAnotherVoiceChat() {
    let timeline = Timeline(events: [
      event("s", .callStarted, sender: .user), voiceCall(at: 0, endedAfter: 30),
      event("r-1", at: 5), event("e", .callEnded, sender: .user, at: 30),
    ])

    #expect(timeline.rows().map(\.id) == ["s", "v"])
  }

  @Test func theCallOnIsALiveEntryAndItsRepliesAreNotChatBubbles() {
    let timeline = Timeline(events: [
      event("before"), voiceCall(at: 10, endedAfter: nil),
      event("s", .callStarted, sender: .user, at: 10), event("r-1", at: 20),
    ])

    #expect(timeline.rows(isInCall: true).map(\.id) == ["before", "v", "s"])
    #expect(timeline.liveVoiceCallID(isInCall: true) == "v")
  }

  @Test func aCallWhoseEndNeverCameLeavesLaterMessagesInTheChat() {
    let timeline = Timeline(events: [voiceCall(endedAfter: nil), event("r-1", at: 20)])

    #expect(timeline.rows(isInCall: false).map(\.id) == ["v", "r-1"])
    #expect(timeline.liveVoiceCallID(isInCall: false) == nil)
  }

  @Test func messagesAfterTheEndTheServiceStoredStayInTheChat() {
    let timeline = Timeline(events: [
      voiceCall(endedAfter: 30), event("r-1", at: 20), event("later", at: 40),
    ])

    #expect(timeline.rows().map(\.id) == ["v", "later"])
  }

  @Test func aCallEndedBeforeItsUpdateCameTakesItsLengthFromTheEnd() {
    let timeline = Timeline(events: [
      voiceCall(endedAfter: nil), event("e", .callEnded, sender: .assistant, at: 48),
    ])

    #expect(timeline.rows().map(\.id) == ["v"])
    #expect(timeline.liveVoiceCallID(isInCall: true) == nil)
    #expect(timeline.voiceChat(of: timeline.events[0]).seconds == 48)
  }

  @Test func anOldVoiceChatStillFoldsItsMessagesIntoItsEnd() {
    let timeline = Timeline(events: [
      event("s", .callStarted, sender: .user), event("u", sender: .user, at: 5),
      event("e", .callEnded, sender: .user, at: 60), voiceCall(at: 100, endedAfter: 30),
      event("r", at: 110),
    ])

    #expect(timeline.rows().map(\.id) == ["s", "e", "v"])
    #expect(timeline.voiceChat(endedBy: timeline.events[2]).lines.map(\.id) == ["u"])
  }

  @Test func aLaterOldStyleCallIsItsOwnVoiceChat() {
    let timeline = Timeline(events: [
      voiceCall(endedAfter: nil), event("s", .callStarted, sender: .user),
      event("s-2", .callStarted, sender: .user, at: 600), event("u", sender: .user, at: 605),
      event("e-2", .callEnded, sender: .user, at: 660),
    ])

    #expect(timeline.rows().map(\.id) == ["v", "s", "s-2", "e-2"])
  }

  @Test func theEntryCannotBeRepliedTo() {
    let timeline = Timeline(events: [event("before"), voiceCall(at: 10, endedAfter: 5)])

    #expect(timeline.rows().map { $0.replyTarget != nil } == [true, false])
  }

  @Test func anUnreadReplyOfTheCallPointsAtItsEntry() {
    let timeline = Timeline(events: [
      event("a"), voiceCall(at: 10, endedAfter: 30), event("r-1", at: 20),
    ])

    #expect(timeline.firstUnreadRowID(after: "a") == "v")
  }

  @Test func transcriptEntriesAreItsLinesWithoutBlankOnes() {
    let start = Date(timeIntervalSince1970: 0)
    let entries = [
      CallTranscriptEntry(
        id: "t-1", callID: "c", seq: 1, speaker: .user, text: "Hi", startedAt: start),
      CallTranscriptEntry(
        id: "t-2", callID: "c", seq: 2, speaker: .assistant, text: "  ", startedAt: start),
      CallTranscriptEntry(
        id: "t-3", callID: "c", seq: 3, speaker: .assistant, text: "Hello", startedAt: start),
    ]

    #expect(
      entries.compactMap(\.line) == [
        TranscriptLine(id: "t-1", text: "Hi", isFromUser: true),
        TranscriptLine(id: "t-3", text: "Hello", isFromUser: false),
      ])
  }
}
