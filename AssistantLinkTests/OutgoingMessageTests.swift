import Foundation
import Synchronization
import Testing

@testable import AssistantLink

struct MessageTextValidationTests {
  @Test(arguments: ["", " ", "\n\t ", "\u{00A0}", "\u{2003}\u{2028}"])
  func emptyAndWhitespaceOnlyTextsAreInvalid(text: String) {
    #expect(!TextValidation.isValidMessage(text))
  }

  @Test func textsWithSurroundingWhitespaceAreValid() {
    #expect(TextValidation.isValidMessage(" Remind me\n"))
  }

  @Test func aNulCharacterMakesTheTextInvalid() {
    #expect(!TextValidation.isValidMessage("a\u{0}b"))
    #expect(!TextValidation.isValidMessage("\u{0}"))
  }

  @Test func fourThousandCodePointsAreValidAndOneMoreIsNot() {
    #expect(TextValidation.isValidMessage(String(repeating: "a", count: 4000)))
    #expect(!TextValidation.isValidMessage(String(repeating: "a", count: 4001)))
  }

  @Test func eachEmojiCountsAsOneCodePoint() {
    #expect(TextValidation.isValidMessage(String(repeating: "😀", count: 4000)))
    #expect(!TextValidation.isValidMessage(String(repeating: "😀", count: 4001)))
  }

  @Test func codePointsAreCountedNotCharacters() {
    let family = "👩‍💻"
    #expect(family.count == 1)
    #expect(TextValidation.isValidMessage(String(repeating: family, count: 1333)))
    #expect(!TextValidation.isValidMessage(String(repeating: family, count: 1334)))
  }
}

struct MessageCaptionTests {
  private func user(
    _ id: String, _ status: Event.DeliveryStatus? = .sent, key: String? = nil
  ) -> Event {
    Event(
      id: id, assistantID: "as-1", type: .textMessage, sender: .user,
      createdAt: Date(timeIntervalSince1970: 0), deliveryStatus: status,
      idempotencyKey: key ?? "key-\(id)", text: id)
  }

  private func outgoing(
    _ key: String, _ state: OutgoingMessage.State = .sending
  ) -> OutgoingMessage {
    OutgoingMessage(
      assistantID: "as-1", idempotencyKey: key, text: key,
      createdAt: Date(timeIntervalSince1970: 1), state: state)
  }

  @Test func onlyTheLatestUserMessageHasACaption() {
    let timeline = Timeline(events: [
      user("e-1", .delivered), user("e-2", .delivered), .stub("e-3"),
    ])

    #expect(timeline.caption(forMessageID: "e-1") == nil)
    #expect(timeline.caption(forMessageID: "e-2") == .delivered)
    #expect(timeline.caption(forMessageID: "e-3") == nil)
  }

  @Test func anOutgoingMessageIsTheLatestAndOlderOnesLoseTheirCaption() {
    let timeline = Timeline(events: [user("e-1")], outgoing: [outgoing("k-1")])

    #expect(timeline.caption(forMessageID: "e-1") == nil)
    #expect(timeline.caption(forMessageID: "k-1") == .sending)
  }

  @Test func onlyTheLatestOfSeveralOutgoingMessagesIsCaptioned() {
    let timeline = Timeline(outgoing: [outgoing("k-1", .failed), outgoing("k-2", .failed)])

    #expect(timeline.caption(forMessageID: "k-1") == nil)
    #expect(timeline.caption(forMessageID: "k-2") == .notDelivered)
  }

  @Test func theCaptionTextsAreTheSpecifiedOnes() {
    #expect(
      [MessageCaption.sending, .sent, .delivered, .notDelivered].map(\.text) == [
        "Sending…", "Sent", "Delivered", "Not Delivered",
      ])
  }

  @Test func receivingTheStoredEventRemovesTheOutgoingMessageWithItsKey() {
    var timeline = Timeline(outgoing: [outgoing("k-1"), outgoing("k-2")])

    timeline.receive(user("e-1", key: "k-1"))

    #expect(timeline.outgoing.map(\.id) == ["k-2"])
    #expect(timeline.events.map(\.id) == ["e-1"])
  }

  @Test func storingAnAlreadyLoadedEventKeepsTheLoadedOne() {
    var timeline = Timeline(events: [user("e-1", .delivered, key: "k-1")])

    let isNew = timeline.store(user("e-1", .sent, key: "k-1"))

    #expect(!isNew)
    #expect(timeline.events.map(\.deliveryStatus) == [.delivered])
  }
}

@MainActor
struct OutgoingMessageTests {
  private let baseURL = URL(string: "https://service.test")!

  private final class Stub: Sendable {
    enum Failure: Sendable {
      case network
      case service(Int, String)
    }

    let events = Mutex(#"{"events": [], "has_more": false}"#)
    let bodies = Mutex<[[String: String]]>([])
    let failures: Mutex<[Failure]>

    init(failures: [Failure] = []) {
      self.failures = Mutex(failures)
    }

    func answer(_ request: URLRequest, _ body: Data?) throws -> (Int, Data) {
      switch (request.httpMethod, request.url?.path()) {
      case ("POST", "/api/v1/assistants/as-1/messages"):
        let sent = try (body?.jsonObject() ?? [:]).compactMapValues { $0 as? String }
        bodies.withLock { $0.append(sent) }
        let failure = failures.withLock { (queue: inout [Failure]) -> Failure? in
          queue.isEmpty ? nil : queue.removeFirst()
        }
        switch failure {
        case .network:
          throw URLError(.notConnectedToInternet)
        case .service(let status, let code):
          return (status, Data(json: #"{"error": {"code": "\#(code)", "message": "No."}}"#))
        case nil:
          let event = OutgoingMessageTests.eventJSON(key: sent["idempotency_key"] ?? "")
          return (201, Data(json: #"{"message": \#(event)}"#))
        }
      case ("GET", "/api/v1/assistants/as-1/events"):
        return (200, Data(json: events.withLock { $0 }))
      default:
        return (200, Data(json: #"{"assistants": [\#(OutgoingMessageTests.hermes)]}"#))
      }
    }
  }

  private nonisolated static let hermes = #"""
    {"id": "as-1", "name": "Hermes", "avatar": "avatar-3", "status": "online", "links": []}
    """#

  private nonisolated static func eventJSON(key: String, status: String = "sent") -> String {
    #"""
    {"id": "ev-\#(key)", "assistant_id": "as-1", "type": "text_message", "sender": "user",
     "link_id": null, "created_at": "2026-10-08T12:30:15Z", "deleted": false,
     "delivery_status": "\#(status)", "idempotency_key": "\#(key)",
     "text_message": {"text": "Hi"}}
    """#
  }

  private func event(
    key: String, status: Event.DeliveryStatus = .sent,
    createdAt: Date = Date(timeIntervalSince1970: 0)
  ) -> Event {
    Event(
      id: "ev-\(key)", assistantID: "as-1", type: .textMessage, sender: .user,
      createdAt: createdAt, deliveryStatus: status, idempotencyKey: key, text: "Hi")
  }

  private func startedModel(_ stub: Stub = Stub()) async -> AppModel {
    let api = APIClient(
      baseURL: baseURL, credential: "ala_secret",
      session: StubURLProtocol.session { request, body in try stub.answer(request, body) })
    let model = AppModel(connect: { api })
    await model.start()
    return model
  }

  private func timeline(_ model: AppModel) -> Timeline {
    model.timelines["as-1"] ?? Timeline()
  }

  @Test func aSentMessageShowsSendingThenSent() async throws {
    let stub = Stub()
    let model = await startedModel(stub)

    let message = try #require(model.queue(text: "Remind me to call David", assistantID: "as-1"))

    #expect(timeline(model).outgoing == [message])
    #expect(timeline(model).caption(forMessageID: message.id) == .sending)
    #expect(model.assistant(id: "as-1")?.latestEvent == nil)

    await model.post(message)

    let sent = stub.bodies.withLock { $0 }
    #expect(sent == [["text": "Remind me to call David", "idempotency_key": message.id]])
    #expect(UUIDv7.date(fromID: message.id) != nil)
    #expect(timeline(model).outgoing.isEmpty)
    #expect(timeline(model).events.map(\.id) == ["ev-\(message.id)"])
    #expect(timeline(model).caption(forMessageID: "ev-\(message.id)") == .sent)
    #expect(model.assistant(id: "as-1")?.latestEvent?.id == "ev-\(message.id)")
  }

  @Test func sendQueuesAndPostsAndReportsWhetherTheTextWasValid() async throws {
    let stub = Stub()
    let model = await startedModel(stub)

    #expect(await model.send(text: "Hi", assistantID: "as-1"))

    #expect(stub.bodies.withLock { $0.count } == 1)
    #expect(timeline(model).events.count == 1)
    #expect(timeline(model).outgoing.isEmpty)
  }

  @Test func eachMessageGetsItsOwnKey() async throws {
    let model = await startedModel(Stub())

    let first = try #require(model.queue(text: "a", assistantID: "as-1"))
    let second = try #require(model.queue(text: "a", assistantID: "as-1"))

    #expect(first.idempotencyKey != second.idempotencyKey)
    #expect(timeline(model).outgoing.map(\.id) == [first.id, second.id])
  }

  @Test func invalidTextsAreNeitherShownNorPosted() async throws {
    let stub = Stub()
    let model = await startedModel(stub)

    for text in ["", "   ", "a\u{0}", String(repeating: "a", count: 4001)] {
      #expect(model.queue(text: text, assistantID: "as-1") == nil)
      #expect(!(await model.send(text: text, assistantID: "as-1")))
    }

    #expect(model.timelines["as-1"] == nil)
    #expect(stub.bodies.withLock { $0.isEmpty })
  }

  @Test func theLiveEventBeforeThePostResponseLeavesNoDuplicate() async throws {
    let stub = Stub()
    let model = await startedModel(stub)
    let message = try #require(model.queue(text: "Hi", assistantID: "as-1"))

    model.apply(created: event(key: message.id))

    await model.post(message)

    #expect(timeline(model).events.map(\.id) == ["ev-\(message.id)"])
    #expect(timeline(model).outgoing.isEmpty)
  }

  @Test func thePostResponseBeforeTheLiveEventLeavesNoDuplicate() async throws {
    let model = await startedModel(Stub())
    let message = try #require(model.queue(text: "Hi", assistantID: "as-1"))

    await model.post(message)
    model.apply(created: event(key: message.id))

    #expect(timeline(model).events.map(\.id) == ["ev-\(message.id)"])
    #expect(timeline(model).outgoing.isEmpty)
  }

  @Test func aDeliveredUpdateBeforeThePostResponseIsNotUndone() async throws {
    let model = await startedModel(Stub())
    let message = try #require(model.queue(text: "Hi", assistantID: "as-1"))
    model.apply(created: event(key: message.id))
    model.apply(updated: event(key: message.id, status: .delivered))

    await model.post(message)

    #expect(timeline(model).caption(forMessageID: "ev-\(message.id)") == .delivered)
    #expect(model.assistant(id: "as-1")?.latestEvent?.deliveryStatus == .delivered)
  }

  @Test func aLiveEventBeforeAPostFailureKeepsTheMessageSent() async throws {
    let model = await startedModel(Stub(failures: [.network]))
    let message = try #require(model.queue(text: "Hi", assistantID: "as-1"))
    model.apply(created: event(key: message.id))

    await model.post(message)

    #expect(timeline(model).outgoing.isEmpty)
    #expect(timeline(model).caption(forMessageID: "ev-\(message.id)") == .sent)
  }

  @Test func theMessageBecomesDeliveredWhenAnyLinkAcknowledgedIt() async throws {
    let model = await startedModel(Stub())
    let message = try #require(model.queue(text: "Hi", assistantID: "as-1"))
    await model.post(message)

    model.apply(updated: event(key: message.id, status: .delivered))

    #expect(timeline(model).caption(forMessageID: "ev-\(message.id)") == .delivered)
  }

  @Test func anUnreachableServiceMakesTheMessageNotDelivered() async throws {
    let model = await startedModel(Stub(failures: [.network]))

    await model.send(text: "Hi", assistantID: "as-1")

    let message = try #require(timeline(model).outgoing.first)
    #expect(message.state == .failed)
    #expect(timeline(model).events.isEmpty)
    #expect(timeline(model).caption(forMessageID: message.id) == .notDelivered)
  }

  @Test(arguments: [
    (500, "internal_error"), (401, "unauthorized"), (404, "not_found"),
    (422, "no_paired_link"), (422, "text_too_long"), (422, "text_empty"),
    (409, "idempotency_key_conflict"),
  ])
  func anyServiceErrorMakesTheMessageNotDelivered(status: Int, code: String) async throws {
    let model = await startedModel(Stub(failures: [.service(status, code)]))

    await model.send(text: "Hi", assistantID: "as-1")

    #expect(timeline(model).outgoing.map(\.state) == [.failed])
  }

  @Test func tryAgainPostsAgainWithTheSameKey() async throws {
    let stub = Stub(failures: [.network])
    let model = await startedModel(stub)
    await model.send(text: "Hi", assistantID: "as-1")
    let failed = try #require(timeline(model).outgoing.first)

    await model.retry(failed)

    let bodies = stub.bodies.withLock { $0 }
    #expect(bodies.count == 2)
    #expect(bodies[0]["idempotency_key"] == failed.id)
    #expect(bodies[1]["idempotency_key"] == failed.id)
    #expect(bodies[1]["text"] == "Hi")
    #expect(timeline(model).outgoing.isEmpty)
    #expect(timeline(model).events.map(\.id) == ["ev-\(failed.id)"])
    #expect(timeline(model).caption(forMessageID: "ev-\(failed.id)") == .sent)
  }

  @Test func aRetryThatFailsAgainStaysNotDelivered() async throws {
    let model = await startedModel(Stub(failures: [.network, .service(500, "internal_error")]))
    await model.send(text: "Hi", assistantID: "as-1")
    let failed = try #require(timeline(model).outgoing.first)

    await model.retry(failed)

    #expect(timeline(model).outgoing.map(\.state) == [.failed])
    #expect(timeline(model).outgoing.map(\.id) == [failed.id])
  }

  @Test func retryingAMessageThatIsNotFailedPostsNothing() async throws {
    let stub = Stub()
    let model = await startedModel(stub)
    let message = try #require(model.queue(text: "Hi", assistantID: "as-1"))

    await model.retry(message)

    #expect(stub.bodies.withLock { $0.isEmpty })
  }

  @Test func cancelRemovesTheFailedMessage() async throws {
    let model = await startedModel(Stub(failures: [.network]))
    await model.send(text: "Hi", assistantID: "as-1")
    let failed = try #require(timeline(model).outgoing.first)

    model.cancel(failed)

    #expect(timeline(model).outgoing.isEmpty)
    #expect(model.failedLatestMessage(assistantID: "as-1") == nil)
  }

  @Test func cancelLeavesAMessageThatIsStillSending() async throws {
    let model = await startedModel(Stub())
    let message = try #require(model.queue(text: "Hi", assistantID: "as-1"))

    model.cancel(message)

    #expect(timeline(model).outgoing == [message])
  }

  @Test func aRefetchWithoutOverlapKeepsTheUnsentMessages() async throws {
    let stub = Stub()
    let first = #"{"events": [\#(Self.eventJSON(key: "a"))], "has_more": true}"#
    stub.events.withLock { $0 = first }
    let model = await startedModel(stub)
    try await model.openConversation(assistantID: "as-1")
    let message = try #require(model.queue(text: "Hi", assistantID: "as-1"))
    let second = #"{"events": [\#(Self.eventJSON(key: "b"))], "has_more": false}"#
    stub.events.withLock { $0 = second }

    try await model.openConversation(assistantID: "as-1")

    #expect(timeline(model).events.map(\.id) == ["ev-b"])
    #expect(timeline(model).outgoing == [message])
  }

  @Test func aRefetchedStoredEventReplacesItsUnsentMessage() async throws {
    let stub = Stub()
    let model = await startedModel(stub)
    try await model.openConversation(assistantID: "as-1")
    let message = try #require(model.queue(text: "Hi", assistantID: "as-1"))
    let other = try #require(model.queue(text: "Ho", assistantID: "as-1"))
    let page = [Self.eventJSON(key: "a"), Self.eventJSON(key: message.id)].joined(separator: ",")
    stub.events.withLock { $0 = #"{"events": [\#(page)], "has_more": false}"# }

    try await model.openConversation(assistantID: "as-1")

    #expect(timeline(model).events.map(\.id) == ["ev-a", "ev-\(message.id)"])
    #expect(timeline(model).outgoing == [other])
  }

  @Test func theFailedLatestMessageFeedsTheAssistantsList() async throws {
    let model = await startedModel(Stub(failures: [.network]))
    let sending = try #require(model.queue(text: "Hi", assistantID: "as-1"))
    #expect(model.failedLatestMessage(assistantID: "as-1") == nil)
    await model.post(sending)

    #expect(model.failedLatestMessage(assistantID: "as-1") == timeline(model).outgoing.first)
    #expect(model.failedLatestMessage(assistantID: "as-1")?.text == "Hi")
    #expect(model.failedLatestMessage(assistantID: "as-2") == nil)
  }

  @Test func aNewerStoredEventHidesTheFailedMessageInTheList() async throws {
    let model = await startedModel(Stub(failures: [.network]))
    await model.send(text: "Hi", assistantID: "as-1")

    model.apply(created: event(key: "later", createdAt: .now.addingTimeInterval(60)))

    #expect(model.failedLatestMessage(assistantID: "as-1") == nil)
  }

  @Test func theModelCaptionsTheLatestUserMessageOfAnAssistant() async throws {
    let model = await startedModel(Stub())
    let message = try #require(model.queue(text: "Hi", assistantID: "as-1"))

    #expect(model.caption(forMessageID: message.id, assistantID: "as-1") == .sending)
    #expect(model.caption(forMessageID: message.id, assistantID: "as-2") == nil)
  }
}
