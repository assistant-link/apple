import Foundation
import Testing

@testable import AssistantLink

struct EventDecodingTests {
  private func decode(_ json: String) throws -> Event {
    try APIClient.decoder.decode(Event.self, from: Data(json: json))
  }

  @Test func decodesTheUsersMessage() throws {
    let event = try decode(
      #"""
      {"id": "e-1", "assistant_id": "as-1", "type": "text_message", "sender": "user",
       "link_id": null, "created_at": "2026-10-08T12:30:15Z", "deleted": false,
       "delivery_status": "sent", "idempotency_key": "k-1", "text_message": {"text": "Hi"}}
      """#)

    #expect(
      event
        == Event(
          id: "e-1", assistantID: "as-1", type: .textMessage, sender: .user,
          createdAt: Date(timeIntervalSince1970: 1_791_462_615), deliveryStatus: .sent,
          idempotencyKey: "k-1", text: "Hi"))
  }

  @Test func decodesAnAssistantMessageWithoutDeliveryStatus() throws {
    let event = try decode(
      #"""
      {"id": "e-2", "assistant_id": "as-1", "type": "text_message", "sender": "assistant",
       "link_id": "l-1", "created_at": "2026-10-08T12:30:15.123456Z", "deleted": false,
       "idempotency_key": null, "text_message": {"text": "Done."}}
      """#)

    #expect(event.sender == .assistant)
    #expect(event.linkID == "l-1")
    #expect(event.deliveryStatus == nil)
    #expect(event.idempotencyKey == nil)
    #expect(event.text == "Done.")
  }

  @Test func decodesADeliveredMessage() throws {
    let event = try decode(
      #"""
      {"id": "e-1", "assistant_id": "as-1", "type": "text_message", "sender": "user",
       "link_id": null, "created_at": "2026-10-08T12:30:15Z", "deleted": false,
       "delivery_status": "delivered", "idempotency_key": "k-1", "text_message": {"text": "Hi"}}
      """#)

    #expect(event.deliveryStatus == .delivered)
  }

  @Test func aDeletedMessageHasNoText() throws {
    let event = try decode(
      #"""
      {"id": "e-1", "assistant_id": "as-1", "type": "text_message", "sender": "user",
       "link_id": null, "created_at": "2026-10-08T12:30:15Z", "deleted": true,
       "delivery_status": "delivered", "idempotency_key": "k-1"}
      """#)

    #expect(event.deleted)
    #expect(event.text == nil)
  }

  @Test func decodesALinkCreatedEvent() throws {
    let event = try decode(
      #"""
      {"id": "e-3", "assistant_id": "as-1", "type": "link_created", "sender": "system",
       "link_id": "l-1", "created_at": "2026-10-08T12:30:15Z", "deleted": false,
       "idempotency_key": null}
      """#)

    #expect(event.type == .linkCreated)
    #expect(event.sender == .system)
    #expect(event.linkID == "l-1")
    #expect(event.text == nil)
    #expect(!event.deleted)
  }

  @Test func rejectsAnUnknownType() {
    #expect(throws: DecodingError.self) {
      try decode(
        #"""
        {"id": "e-3", "assistant_id": "as-1", "type": "poll", "sender": "system",
         "link_id": null, "created_at": "2026-10-08T12:30:15Z", "deleted": false}
        """#)
    }
  }
}

struct EventAPITests {
  private let baseURL = URL(string: "https://service.test")!

  private let message = #"""
    {"id": "e-1", "assistant_id": "as-1", "type": "text_message", "sender": "user",
     "link_id": null, "created_at": "2026-10-08T12:30:15Z", "deleted": false,
     "delivery_status": "sent", "idempotency_key": "k-1", "text_message": {"text": "Hi"}}
    """#

  private func client(_ handler: @escaping StubURLProtocol.Handler) -> APIClient {
    APIClient(
      baseURL: baseURL, credential: "ala_secret", session: StubURLProtocol.session(handler))
  }

  private static func queryItems(_ request: URLRequest) -> [String: String] {
    let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
    return Dictionary(uniqueKeysWithValues: (items ?? []).map { ($0.name, $0.value ?? "") })
  }

  @Test func assistantsCarryTheirLatestEvent() async throws {
    let api = client { [message] _, _ in
      (
        200,
        Data(
          json: #"""
            {"assistants": [
              {"id": "as-1", "name": "Hermes", "avatar": "avatar-3", "status": "online",
               "links": [], "latest_event": \#(message)},
              {"id": "as-2", "name": "Muse", "avatar": "avatar-1", "status": "offline",
               "links": [], "latest_event": null}
            ]}
            """#)
      )
    }

    let assistants = try await api.listAssistants()

    #expect(assistants[0].latestEvent?.id == "e-1")
    #expect(assistants[0].latestEvent?.text == "Hi")
    #expect(assistants[1].latestEvent == nil)
  }

  @Test func eventsRequestTheLatestPage() async throws {
    let api = client { request, _ in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path() == "/api/v1/assistants/as-1/events")
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ala_secret")
      #expect(Self.queryItems(request) == ["limit": "50"])
      return (200, Data(json: #"{"events": [], "has_more": false}"#))
    }

    let page = try await api.events(assistantID: "as-1", limit: 50)

    #expect(page == EventPage(events: [], hasMore: false))
  }

  @Test func eventsRequestThePageBeforeAnEvent() async throws {
    let api = client { [message] request, _ in
      #expect(Self.queryItems(request) == ["limit": "50", "before": "e-9"])
      return (200, Data(json: #"{"events": [\#(message)], "has_more": true}"#))
    }

    let page = try await api.events(assistantID: "as-1", limit: 50, before: "e-9")

    #expect(page.events.map(\.id) == ["e-1"])
    #expect(page.hasMore)
  }

  @Test func eventsFailWithTheServicesError() async {
    let api = client { _, _ in
      (
        422,
        Data(json: #"{"error": {"code": "invalid_params", "message": "Unknown event."}}"#)
      )
    }

    await #expect(
      throws: APIError.service(status: 422, code: "invalid_params", message: "Unknown event.")
    ) {
      try await api.events(assistantID: "as-1", limit: 50, before: "e-9")
    }
  }

  @Test(arguments: [200, 201])
  func sendMessagePostsTheTextWithItsIdempotencyKey(status: Int) async throws {
    let api = client { [message] request, body in
      #expect(request.httpMethod == "POST")
      #expect(request.url?.path() == "/api/v1/assistants/as-1/messages")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
      let json = try #require(try body?.jsonObject())
      #expect(json as? [String: String] == ["text": "Hi", "idempotency_key": "k-1"])
      return (status, Data(json: #"{"message": \#(message)}"#))
    }

    let event = try await api.sendMessage(assistantID: "as-1", text: "Hi", idempotencyKey: "k-1")

    #expect(event.id == "e-1")
    #expect(event.idempotencyKey == "k-1")
    #expect(event.deliveryStatus == .sent)
  }

  @Test func sendMessageFailsWithTheServicesError() async {
    let api = client { _, _ in
      (
        422,
        Data(json: #"{"error": {"code": "no_paired_link", "message": "No paired Link."}}"#)
      )
    }

    await #expect(
      throws: APIError.service(status: 422, code: "no_paired_link", message: "No paired Link.")
    ) {
      try await api.sendMessage(assistantID: "as-1", text: "Hi", idempotencyKey: "k-1")
    }
  }

  @Test func sendMessageReportsAnUnreachableService() async {
    let api = client { _, _ in throw URLError(.notConnectedToInternet) }

    await #expect(throws: APIError.unreachable) {
      try await api.sendMessage(assistantID: "as-1", text: "Hi", idempotencyKey: "k-1")
    }
  }
}
