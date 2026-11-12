import Foundation
import Testing

@testable import AssistantLink

/// The service may add enum values, fields and kinds of items before this app knows them.
struct ForwardCompatibilityTests {
  private let baseURL = URL(string: "https://service.test")!

  private func client(responding json: String) -> APIClient {
    APIClient(
      baseURL: baseURL, credential: "ala_secret",
      session: StubURLProtocol.session { _, _ in (200, Data(json: json)) })
  }

  private func decodeEvent(_ json: String) throws -> Event {
    try APIClient.decoder.decode(Event.self, from: Data(json: json))
  }

  @Test func unknownEventValuesDecodeAsUnknown() throws {
    let event = try decodeEvent(
      #"""
      {"id": "e-1", "assistant_id": "as-1", "type": "poll", "sender": "moderator",
       "link_id": null, "created_at": "2026-10-08T12:30:15Z", "deleted": false,
       "delivery_status": "read", "idempotency_key": "k-1"}
      """#)

    #expect(event.type == .unknown)
    #expect(event.sender == .unknown)
    #expect(event.deliveryStatus == .unknown)
  }

  @Test func anEventWithoutItsOptionalFieldsDecodes() throws {
    let event = try decodeEvent(
      #"""
      {"id": "e-1", "assistant_id": "as-1", "type": "text_message", "sender": "assistant",
       "created_at": "2026-10-08T12:30:15Z", "text_message": {"text": "Hi"}}
      """#)

    #expect(
      event
        == Event(
          id: "e-1", assistantID: "as-1", type: .textMessage, sender: .assistant,
          createdAt: Date(timeIntervalSince1970: 1_791_462_615), text: "Hi"))
  }

  @Test func extraFieldsAreIgnored() throws {
    let event = try decodeEvent(
      #"""
      {"id": "e-1", "assistant_id": "as-1", "type": "text_message", "sender": "user",
       "link_id": null, "created_at": "2026-10-08T12:30:15Z", "deleted": false,
       "delivery_status": "sent", "idempotency_key": "k-1", "reactions": ["👍"],
       "text_message": {"text": "Hi", "language": "en", "via": "voice"}}
      """#)

    #expect(event.text == "Hi")
    #expect(event.via == .voice)
    #expect(event.deliveryStatus == .sent)
  }

  @Test func assistantsSkipTheItemsTheyCannotDecode() async throws {
    let api = client(
      responding: #"""
        {"assistants": [
          {"id": "as-1", "name": "Hermes", "avatar": "avatar-3", "status": "dreaming",
           "color": "teal",
           "links": [
             {"id": "l-1", "label": "Mac", "status": "hibernating", "platform": "macos"},
             {"label": "No id", "status": "online"},
             {"id": "l-2", "status": "idle"}
           ]},
          {"name": "No id", "avatar": "avatar-1", "status": "online", "links": []},
          {"id": "as-2", "name": "Muse", "avatar": "avatar-1", "status": "online",
           "links": "not a list"},
          {"id": "as-3", "name": "Iris", "avatar": "avatar-2", "status": "offline",
           "links": [], "latest_event": {"id": "e-1", "type": "text_message"}}
        ],
        "next_cursor": null}
        """#)

    let assistants = try await api.listAssistants()

    #expect(assistants.map(\.id) == ["as-1", "as-3"])
    #expect(assistants[0].status == .offline)
    #expect(assistants[0].links.map(\.id) == ["l-1", "l-2"])
    #expect(assistants[0].links.map(\.status) == [.offline, .idle])
    #expect(assistants[0].links[1].label == nil)
    #expect(assistants[0].links[1].lastActiveAt == nil)
    #expect(assistants[1].latestEvent == nil)
  }

  @Test func anEventPageSkipsTheEventsItCannotDecode() async throws {
    let api = client(
      responding: #"""
        {"events": [
          {"id": "e-1", "assistant_id": "as-1", "type": "text_message", "sender": "user",
           "created_at": "2026-10-08T12:30:15Z", "text_message": {"text": "Hi"}},
          {"assistant_id": "as-1", "type": "text_message", "sender": "user",
           "created_at": "2026-10-08T12:30:16Z", "text_message": {"text": "No id"}},
          {"id": "e-3", "assistant_id": "as-1", "type": "text_message", "sender": "user",
           "created_at": "yesterday"},
          {"id": "e-4", "assistant_id": "as-1", "type": "reaction", "sender": "assistant",
           "created_at": "2026-10-08T12:30:18Z", "reaction": {"emoji": "👍"}}
        ],
        "has_more": true, "cursor": "abc"}
        """#)

    let page = try await api.events(assistantID: "as-1", limit: 50)

    #expect(page.events.map(\.id) == ["e-1", "e-4"])
    #expect(page.events[1].type == .unknown)
    #expect(page.hasMore)
  }

  @Test func aListOfOnlyBadItemsIsEmpty() async throws {
    let api = client(responding: #"{"assistants": [{"id": 1}, null, "as-1"]}"#)

    #expect(try await api.listAssistants().isEmpty)
  }

  @Test func aMissingListStillFailsTheResponse() async {
    let api = client(responding: #"{"has_more": false}"#)

    await #expect(throws: APIError.unexpectedResponse(status: 200)) {
      try await api.events(assistantID: "as-1", limit: 50)
    }
  }

  @Test func aLiveEventOfAnUnknownTypeArrivesAsUnknown() {
    let message = LiveMessage(
      text: #"""
        {"jsonrpc": "2.0", "method": "event.created", "params": {"event": {
          "id": "e-1", "assistant_id": "as-1", "type": "poll", "sender": "moderator",
          "created_at": "2026-10-08T12:30:15Z", "poll": {"question": "?"}}}}
        """#)

    #expect(
      message
        == .eventCreated(
          Event(
            id: "e-1", assistantID: "as-1", type: .unknown, sender: .unknown,
            createdAt: Date(timeIntervalSince1970: 1_791_462_615))))
  }

  @Test func aLiveLinkStatusThisAppDoesNotKnowIsOffline() {
    let message = LiveMessage(
      text: #"""
        {"jsonrpc": "2.0", "method": "link.status",
         "params": {"link_id": "l-1", "status": "hibernating"}}
        """#)

    #expect(message == .linkStatus(LinkStatusChange(linkID: "l-1", status: .offline)))
  }

  @Test func anUnknownEventHasNoCaptionOrPreview() {
    let event = Event(
      id: "e-1", assistantID: "as-1", type: .unknown, sender: .unknown,
      createdAt: Date(timeIntervalSince1970: 1_791_462_615), deliveryStatus: .unknown)
    let message = Event(
      id: "e-2", assistantID: "as-1", type: .textMessage, sender: .user,
      createdAt: Date(timeIntervalSince1970: 1_791_462_615), deliveryStatus: .unknown,
      text: "Hi")

    #expect(ListPreview(event: event, failedMessage: nil).text == "")
    #expect(Timeline(events: [event, message]).caption(forMessageID: "e-2") == nil)
  }
}
