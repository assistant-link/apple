import Foundation
import Synchronization
import Testing

@testable import AssistantLink

@MainActor
struct PushNotificationTests {
  private let baseURL = URL(string: "https://service.test")!

  private nonisolated static func hermes(linkStatus: String) -> String {
    #"""
    {"id": "as-1", "name": "Hermes", "avatar": "avatar-3", "status": "offline", "links": [
      {"id": "l-1", "label": null, "status": "\#(linkStatus)", "last_active_at": null}
    ]}
    """#
  }

  private nonisolated static let paired = hermes(linkStatus: "offline")

  /// Records the push token requests, answers them with `tokenStatuses` and lists `assistants`.
  private final class Service: Sendable {
    let tokenRequests = Mutex<[String]>([])
    let tokenStatuses: Mutex<[Int]>
    let assistants: String

    init(assistants: String = "", tokenStatuses: [Int] = []) {
      self.assistants = assistants
      self.tokenStatuses = Mutex(tokenStatuses)
    }

    func respond(to request: URLRequest, body: Data?) throws -> (Int, Data) {
      guard request.url?.path() == "/api/v1/device/push_token" else {
        return (200, Data(json: #"{"assistants": [\#(assistants)]}"#))
      }
      let token = try body?.jsonObject()["token"] as? String
      let entry = token.map { "\(request.httpMethod!) \($0)" } ?? request.httpMethod!
      tokenRequests.withLock { $0.append(entry) }
      let status = tokenStatuses.withLock { $0.isEmpty ? 204 : $0.removeFirst() }
      return (status, Data())
    }

    var requests: [String] { tokenRequests.withLock { $0 } }
  }

  private func model(
    _ service: Service, enableNotifications: @escaping @MainActor () -> Void = {},
    sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
  ) -> AppModel {
    let api = APIClient(
      baseURL: baseURL, credential: "ala_secret",
      session: StubURLProtocol.session { try service.respond(to: $0, body: $1) })
    return AppModel(
      connect: { api }, sleep: sleep, dictation: .fake(),
      enableNotifications: enableNotifications)
  }

  @Test func theTokenIsHex() {
    #expect(PushNotifications.hex(Data([0x0a, 0xff, 0x00, 0x7b])) == "0aff007b")
  }

  @Test func aReceivedTokenIsUploadedAsHex() async {
    let service = Service()
    let model = model(service)
    await model.start()

    model.received(pushToken: Data([0xbe, 0xef]))
    await model.pushTokenUpload?.value

    #expect(service.requests == ["PUT beef"])
  }

  @Test func aTokenReceivedBeforeTheAccountIsUploadedOnceItStarts() async {
    let service = Service()
    let model = model(service)

    model.received(pushToken: Data([0xbe, 0xef]))
    #expect(model.pushTokenUpload == nil)
    await model.start()
    await model.pushTokenUpload?.value

    #expect(service.requests == ["PUT beef"])
  }

  @Test func aChangedTokenIsUploadedAgain() async {
    let service = Service()
    let model = model(service)
    await model.start()

    model.received(pushToken: Data([0xbe, 0xef]))
    await model.pushTokenUpload?.value
    model.received(pushToken: Data([0xca, 0xfe]))
    await model.pushTokenUpload?.value

    #expect(service.requests == ["PUT beef", "PUT cafe"])
  }

  @Test func aTransientUploadFailureIsRetried() async {
    let service = Service(tokenStatuses: [503, 503])
    let model = model(service)
    await model.start()

    model.received(pushToken: Data([0xbe, 0xef]))
    await model.pushTokenUpload?.value

    #expect(service.requests == ["PUT beef", "PUT beef", "PUT beef"])
  }

  @Test func aRejectedTokenIsNotRetried() async {
    let service = Service(tokenStatuses: [422])
    let model = model(service)
    await model.start()

    model.received(pushToken: Data([0xbe, 0xef]))
    await model.pushTokenUpload?.value

    #expect(service.requests == ["PUT beef"])
  }

  @Test func logOutRemovesTheTokenAndUploadsItForTheNewAccount() async throws {
    let service = Service()
    let model = model(service)
    await model.start()
    model.received(pushToken: Data([0xbe, 0xef]))
    await model.pushTokenUpload?.value

    try await model.logOut()
    await model.pushTokenUpload?.value

    #expect(service.requests == ["PUT beef", "DELETE", "PUT beef"])
  }

  @Test func logOutStopsARetryingUploadSoItCannotRestoreTheToken() async throws {
    let service = Service(tokenStatuses: [503])
    // The retry would wake once the token is removed, while the old account still exists.
    let model = model(
      service,
      sleep: { _ in
        while !service.requests.contains("DELETE") { try await Task.sleep(for: .milliseconds(1)) }
      })
    await model.start()
    model.received(pushToken: Data([0xbe, 0xef]))
    while service.requests.isEmpty { try await Task.sleep(for: .milliseconds(1)) }

    try await model.logOut()
    await model.pushTokenUpload?.value

    #expect(service.requests == ["PUT beef", "DELETE", "PUT beef"])
  }

  @Test func notificationsAreEnabledOnceAPairedLinkIsKnown() async throws {
    let enabled = Mutex(0)
    let model = model(Service(assistants: Self.paired)) { enabled.withLock { $0 += 1 } }

    await model.start()
    try await model.refresh()

    #expect(enabled.withLock { $0 } == 1)
  }

  @Test func notificationsWaitForTheFirstPairing() async throws {
    let enabled = Mutex(0)
    let service = Service(assistants: Self.hermes(linkStatus: "not_paired"))
    let model = model(service) { enabled.withLock { $0 += 1 } }

    await model.start()
    #expect(enabled.withLock { $0 } == 0)
    model.apply(LinkStatusChange(linkID: "l-1", status: .online, lastActiveAt: .now))

    #expect(enabled.withLock { $0 } == 1)
  }

  @Test func aPushReadsItsAssistant() {
    let push = Push(userInfo: [
      "aps": ["thread-id": "l-1"],
      "link_id": "l-1", "assistant_id": "as-1", "event_id": "e-1", "priority": "high",
    ])

    #expect(push == Push(assistantID: "as-1"))
  }

  @Test func aPushWithoutAUsableAssistantReadsAsNone() {
    #expect(Push(userInfo: [:]) == Push(assistantID: nil))
    #expect(Push(userInfo: ["assistant_id": 42]) == Push(assistantID: nil))
  }

  @Test func onlyTheConversationOnScreenHidesItsBanners() {
    let model = model(Service())

    #expect(model.showsBanner(for: Push(assistantID: "as-1")))
    model.navigated(to: [.conversation("as-1")])
    #expect(!model.showsBanner(for: Push(assistantID: "as-1")))
    #expect(model.showsBanner(for: Push(assistantID: "as-2")))
    #expect(model.showsBanner(for: Push(assistantID: nil)))
    model.navigated(to: [.conversation("as-1"), .details("as-1")])
    #expect(model.showsBanner(for: Push(assistantID: "as-1")))
    model.navigated(to: [])
    #expect(model.showsBanner(for: Push(assistantID: "as-1")))
  }

  @Test func aTappedPushOpensItsConversationOnceTheAssistantsHaveLoaded() async {
    let model = model(Service(assistants: Self.paired))

    model.open(Push(assistantID: "as-1"))
    #expect(model.takeConversationToOpen() == nil)
    await model.start()

    #expect(model.takeConversationToOpen() == "as-1")
    #expect(model.takeConversationToOpen() == nil)
  }

  @Test func aTappedPushForAnUnknownAssistantOpensNothing() async {
    let model = model(Service(assistants: Self.paired))
    await model.start()

    model.open(Push(assistantID: "as-9"))
    #expect(model.conversationToOpen == nil)
    model.open(Push(assistantID: nil))

    #expect(model.conversationToOpen == nil)
  }
}
