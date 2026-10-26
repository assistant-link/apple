import Foundation
import Synchronization
import Testing

@testable import AssistantLink

@MainActor
struct AppModelTests {
  private let baseURL = URL(string: "https://service.test")!

  private let hermes = #"""
    {"id": "as-1", "name": "Hermes", "avatar": "avatar-3", "status": "offline", "links": []}
    """#

  private func model(_ handler: @escaping StubURLProtocol.Handler) -> AppModel {
    let api = APIClient(
      baseURL: baseURL, credential: "ala_secret", session: StubURLProtocol.session(handler))
    return AppModel(connect: { api })
  }

  private nonisolated static func pairingJSON(code: String, expiresIn seconds: TimeInterval) -> Data
  {
    let expiresAt = Date.now.addingTimeInterval(seconds).formatted(.iso8601)
    return Data(
      json: #"{"code": "\#(code)", "expires_at": "\#(expiresAt)", "pairing_text": "\#(code)"}"#)
  }

  @Test func startLoadsTheAssistants() async throws {
    let model = model { _, _ in (200, Data(json: #"{"assistants": [\#(hermes)]}"#)) }

    await model.start()

    #expect(model.phase == .ready)
    #expect(model.assistants.map(\.name) == ["Hermes"])
  }

  @Test func startReportsFailures() async throws {
    let model = model { _, _ in throw URLError(.notConnectedToInternet) }

    await model.start()

    #expect(model.phase == .failed(APIError.unreachable.localizedDescription))
  }

  @Test func createdAssistantsAreAppended() async throws {
    let model = model { request, _ in
      request.httpMethod == "GET"
        ? (200, Data(json: #"{"assistants": []}"#))
        : (201, Data(json: #"{"assistant": \#(hermes)}"#))
    }
    await model.start()

    let assistant = try await model.createAssistant(name: "Hermes", avatar: "avatar-3")

    #expect(model.assistants == [assistant])
  }

  @Test func createdLinksAreAddedToTheirAssistant() async throws {
    let model = model { request, _ in
      request.httpMethod == "GET"
        ? (200, Data(json: #"{"assistants": [\#(hermes)]}"#))
        : (
          201,
          Data(
            json: #"""
              {"link": {"id": "l-1", "label": "laptop", "status": "not_paired",
                        "last_active_at": null}}
              """#)
        )
    }
    await model.start()

    let link = try await model.createLink(assistantID: "as-1")

    #expect(model.assistant(id: "as-1")?.links == [link])
  }

  @Test func pairingCodesAreReusedUntilANewOneIsRequested() async throws {
    let issued = Mutex(0)
    let model = model { _, _ in
      let count = issued.withLock {
        $0 += 1
        return $0
      }
      return (201, Self.pairingJSON(code: "CODE-000\(count)", expiresIn: 900))
    }

    let first = try await model.pairingCode(linkID: "l-1")
    let again = try await model.pairingCode(linkID: "l-1")
    let renewed = try await model.pairingCode(linkID: "l-1", renew: true)

    #expect(first.code == "CODE-0001")
    #expect(again == first)
    #expect(renewed.code == "CODE-0002")
  }

  @Test func expiredPairingCodesAreReplaced() async throws {
    let issued = Mutex(0)
    let model = model { _, _ in
      let count = issued.withLock {
        $0 += 1
        return $0
      }
      return (201, Self.pairingJSON(code: "CODE-000\(count)", expiresIn: count == 1 ? -1 : 900))
    }

    _ = try await model.pairingCode(linkID: "l-1")
    let next = try await model.pairingCode(linkID: "l-1")

    #expect(next.code == "CODE-0002")
  }

  private let twoLinks = #"""
    {"id": "as-1", "name": "Hermes", "avatar": "avatar-3", "status": "offline", "links": [
      {"id": "l-1", "label": null, "status": "offline", "last_active_at": null},
      {"id": "l-2", "label": null, "status": "not_paired", "last_active_at": null}
    ]}
    """#

  @Test func linkStatusUpdatesTheLinkAndItsAssistant() async throws {
    let model = model { _, _ in (200, Data(json: #"{"assistants": [\#(twoLinks)]}"#)) }
    await model.start()
    let connectedAt = Date(timeIntervalSince1970: 1_791_462_615)
    let disconnectedAt = connectedAt.addingTimeInterval(60)

    model.apply(LinkStatusChange(linkID: "l-1", status: .online, lastActiveAt: connectedAt))
    let online = try #require(model.assistant(id: "as-1"))
    model.apply(LinkStatusChange(linkID: "l-1", status: .offline, lastActiveAt: disconnectedAt))
    let offline = try #require(model.assistant(id: "as-1"))

    #expect(online.status == .online)
    #expect(online.links.map(\.status) == [.online, .notPaired])
    #expect(online.links[0].lastActiveAt == connectedAt)
    #expect(offline.status == .offline)
    #expect(offline.links.map(\.status) == [.offline, .notPaired])
    #expect(offline.links[0].lastActiveAt == disconnectedAt)
  }

  @Test func linkStatusForAnUnknownLinkChangesNothing() async throws {
    let model = model { _, _ in (200, Data(json: #"{"assistants": [\#(twoLinks)]}"#)) }
    await model.start()
    let before = model.assistants

    model.apply(LinkStatusChange(linkID: "l-9", status: .online, lastActiveAt: .now))

    #expect(model.assistants == before)
  }

  @Test func liveUpdatesRefetchOnOpenAndApplyStatus() async throws {
    let fetches = Mutex(0)
    let api = APIClient(
      baseURL: baseURL, credential: "ala_secret",
      session: StubURLProtocol.session { [twoLinks] _, _ in
        let count = fetches.withLock {
          $0 += 1
          return $0
        }
        let assistants = count == 1 ? "" : twoLinks
        return (200, Data(json: #"{"assistants": [\#(assistants)]}"#))
      })
    let messages = [
      #"{"jsonrpc": "2.0", "method": "link.status", "params": {"link_id": "l-1", "status": "online", "last_active_at": null}}"#,
      #"{"jsonrpc": "2.0", "method": "connection.closing", "params": {"reason": "account_deleted"}}"#,
    ]
    let model = AppModel(
      connect: { api },
      liveUpdates: { _ in
        LiveUpdates(
          connect: {
            AsyncThrowingStream { continuation in
              continuation.yield(.opened)
              for message in messages { continuation.yield(.message(message)) }
              continuation.finish()
            }
          },
          sleep: { _ in }, uptime: { .zero }, backoff: Backoff(jitter: { 1 }))
      })
    await model.start()

    await model.runLiveUpdates()

    #expect(fetches.withLock { $0 } == 2)
    #expect(model.assistant(id: "as-1")?.links.map(\.status) == [.online, .notPaired])
    #expect(model.assistant(id: "as-1")?.status == .online)
  }

  private nonisolated static func eventJSON(_ id: String) -> String {
    #"""
    {"id": "\#(id)", "assistant_id": "as-1", "type": "text_message", "sender": "assistant",
     "link_id": "l-1", "created_at": "2026-10-08T12:30:15Z", "deleted": false,
     "idempotency_key": null, "text_message": {"text": "\#(id)"}}
    """#
  }

  private nonisolated static func pageJSON(_ ids: [String], hasMore: Bool = false) -> String {
    let events = ids.map { eventJSON($0) }.joined(separator: ",")
    return #"{"events": [\#(events)], "has_more": \#(hasMore)}"#
  }

  private nonisolated static func eventsPath(_ request: URLRequest) -> Bool {
    request.url?.path() == "/api/v1/assistants/as-1/events"
  }

  private nonisolated static func query(_ request: URLRequest) -> [String: String] {
    let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
    return Dictionary(uniqueKeysWithValues: (items ?? []).map { ($0.name, $0.value ?? "") })
  }

  /// A client whose Assistant "as-1" answers its events requests from `page`.
  private func eventsAPI(
    _ page: @escaping @Sendable ([String: String]) -> String
  ) -> APIClient {
    APIClient(
      baseURL: baseURL, credential: "ala_secret",
      session: StubURLProtocol.session { [hermes] request, _ in
        if Self.eventsPath(request) {
          return (200, Data(json: page(Self.query(request))))
        }
        return (200, Data(json: #"{"assistants": [\#(hermes)]}"#))
      })
  }

  private func liveModel(api: APIClient, messages: [String]) -> AppModel {
    AppModel(
      connect: { api },
      liveUpdates: { _ in
        LiveUpdates(
          connect: {
            AsyncThrowingStream { continuation in
              continuation.yield(.opened)
              for message in messages { continuation.yield(.message(message)) }
              continuation.finish()
            }
          },
          sleep: { _ in }, uptime: { .zero }, backoff: Backoff(jitter: { 1 }))
      })
  }

  private static let accountDeleted =
    #"{"jsonrpc": "2.0", "method": "connection.closing", "params": {"reason": "account_deleted"}}"#

  @Test func openingAConversationLoadsTheLatestFiftyEvents() async throws {
    let queries = Mutex<[[String: String]]>([])
    let api = eventsAPI { query in
      queries.withLock { $0.append(query) }
      return Self.pageJSON(["e-1", "e-2"], hasMore: true)
    }
    let model = AppModel(connect: { api })
    await model.start()

    try await model.openConversation(assistantID: "as-1")

    #expect(queries.withLock { $0 } == [["limit": "50"]])
    #expect(model.timelines["as-1"]?.events.map(\.id) == ["e-1", "e-2"])
    #expect(model.timelines["as-1"]?.hasMore == true)
    #expect(model.assistant(id: "as-1")?.latestEvent?.id == "e-2")
  }

  @Test func loadingEarlierPrependsThe50EventsBeforeTheOldestWithoutDuplicates() async throws {
    let queries = Mutex<[[String: String]]>([])
    let api = eventsAPI { query in
      queries.withLock { $0.append(query) }
      return query["before"] == nil
        ? Self.pageJSON(["e-3", "e-4"], hasMore: true) : Self.pageJSON(["e-2", "e-3"])
    }
    let model = AppModel(connect: { api })
    await model.start()
    try await model.openConversation(assistantID: "as-1")

    try await model.loadEarlier(assistantID: "as-1")

    #expect(queries.withLock { $0.last } == ["limit": "50", "before": "e-3"])
    #expect(model.timelines["as-1"]?.events.map(\.id) == ["e-2", "e-3", "e-4"])
    #expect(model.timelines["as-1"]?.hasMore == false)
  }

  @Test func loadingEarlierWithoutAConversationRequestsNothing() async throws {
    let api = eventsAPI { _ in
      Issue.record("unexpected events request")
      return Self.pageJSON([])
    }
    let model = AppModel(connect: { api })
    await model.start()

    try await model.loadEarlier(assistantID: "as-1")

    #expect(model.timelines.isEmpty)
  }

  @Test func createdEventsAreAppendedAndBecomeTheLatestEvent() async throws {
    let api = eventsAPI { _ in Self.pageJSON(["e-1"]) }
    let model = AppModel(connect: { api })
    await model.start()

    model.apply(created: .stub("e-0"))
    #expect(model.timelines["as-1"] == nil)
    #expect(model.assistant(id: "as-1")?.latestEvent?.id == "e-0")

    try await model.openConversation(assistantID: "as-1")
    model.apply(created: .stub("e-2"))

    #expect(model.timelines["as-1"]?.events.map(\.id) == ["e-1", "e-2"])
    #expect(model.assistant(id: "as-1")?.latestEvent?.id == "e-2")
  }

  @Test func updatedEventsReplaceTheLoadedOne() async throws {
    let api = eventsAPI { _ in Self.pageJSON(["e-1", "e-2"]) }
    let model = AppModel(connect: { api })
    await model.start()
    try await model.openConversation(assistantID: "as-1")
    var delivered = Event.stub("e-2")
    delivered.deliveryStatus = .delivered

    model.apply(updated: delivered)
    model.apply(updated: .stub("e-0"))

    #expect(model.timelines["as-1"]?.events.map(\.id) == ["e-1", "e-2"])
    #expect(model.timelines["as-1"]?.events.last?.deliveryStatus == .delivered)
    #expect(model.assistant(id: "as-1")?.latestEvent?.deliveryStatus == .delivered)
    #expect(model.assistant(id: "as-1")?.latestEvent?.id == "e-2")
  }

  @Test func reconnectingRefetchesTheLatestEventsAndMergesOverlap() async throws {
    let fetches = Mutex(0)
    let api = eventsAPI { _ in
      let count = fetches.withLock {
        $0 += 1
        return $0
      }
      return Self.pageJSON(count == 1 ? ["e-1", "e-2"] : ["e-2", "e-3"])
    }
    let created = #"""
      {"jsonrpc": "2.0", "method": "event.created", "params": {"event": \#(Self.eventJSON("e-4"))}}
      """#
    let model = liveModel(api: api, messages: [created, Self.accountDeleted])
    await model.start()
    try await model.openConversation(assistantID: "as-1")

    await model.runLiveUpdates()

    #expect(fetches.withLock { $0 } == 2)
    #expect(model.timelines["as-1"]?.events.map(\.id) == ["e-1", "e-2", "e-3", "e-4"])
    #expect(model.assistant(id: "as-1")?.latestEvent?.id == "e-4")
  }

  @Test func reconnectingReplacesTheEventsWhenNothingOverlaps() async throws {
    let fetches = Mutex(0)
    let api = eventsAPI { _ in
      let count = fetches.withLock {
        $0 += 1
        return $0
      }
      return Self.pageJSON(count == 1 ? ["e-1", "e-2"] : ["e-8", "e-9"], hasMore: count > 1)
    }
    let model = liveModel(api: api, messages: [Self.accountDeleted])
    await model.start()
    try await model.openConversation(assistantID: "as-1")

    await model.runLiveUpdates()

    #expect(model.timelines["as-1"]?.events.map(\.id) == ["e-8", "e-9"])
    #expect(model.timelines["as-1"]?.hasMore == true)
  }

  @Test func reconnectingDoesNotLoadConversationsThatWereNeverOpened() async throws {
    let api = eventsAPI { _ in
      Issue.record("unexpected events request")
      return Self.pageJSON([])
    }
    let model = liveModel(api: api, messages: [Self.accountDeleted])
    await model.start()

    await model.runLiveUpdates()

    #expect(model.timelines.isEmpty)
  }

  private final class Requests: Sendable {
    let log = Mutex<[String]>([])

    func record(_ request: URLRequest) {
      let credential = request.value(forHTTPHeaderField: "Authorization") ?? "none"
      log.withLock { $0.append("\(request.httpMethod!) \(request.url!.path()) \(credential)") }
    }

    var all: [String] { log.withLock { $0 } }
  }

  private func accountModel(
    store: InMemoryCredentialStore, requests: Requests,
    deleteAccount: @escaping @Sendable () throws -> (Int, Data) = { (204, Data()) }
  ) -> AppModel {
    let session = StubURLProtocol.session { [hermes] request, _ in
      requests.record(request)
      switch (request.httpMethod, request.url!.path()) {
      case ("POST", "/api/v1/accounts"):
        return (201, Data(json: #"{"account_id": "acc-2", "credential": "ala_new"}"#))
      case ("DELETE", "/api/v1/account"):
        return try deleteAccount()
      default:
        let isOld = request.value(forHTTPHeaderField: "Authorization") == "Bearer ala_old"
        return (200, Data(json: #"{"assistants": [\#(isOld ? hermes : "")]}"#))
      }
    }
    return AppModel(
      connect: { [baseURL] in
        try await AccountSession.connect(baseURL: baseURL, store: store, session: session)
      },
      forget: { try store.delete() })
  }

  @Test func logOutDeletesTheAccountAndStartsAFreshOne() async throws {
    let store = InMemoryCredentialStore("ala_old")
    let requests = Requests()
    let model = accountModel(store: store, requests: requests)
    await model.start()
    let firstSession = model.session

    try await model.logOut()

    #expect(
      requests.all == [
        "GET /api/v1/assistants Bearer ala_old",
        "DELETE /api/v1/account Bearer ala_old",
        "POST /api/v1/accounts none",
        "GET /api/v1/assistants Bearer ala_new",
      ])
    #expect(try store.load() == "ala_new")
    #expect(model.phase == .ready)
    #expect(model.assistants.isEmpty)
    #expect(model.session != firstSession)
  }

  @Test func aFailedLogOutDeletesNothing() async throws {
    let store = InMemoryCredentialStore("ala_old")
    let requests = Requests()
    let model = accountModel(store: store, requests: requests) {
      throw URLError(.notConnectedToInternet)
    }
    await model.start()
    let firstSession = model.session

    await #expect(throws: APIError.unreachable) { try await model.logOut() }

    #expect(try store.load() == "ala_old")
    #expect(model.assistants.map(\.name) == ["Hermes"])
    #expect(model.session == firstSession)
    #expect(!requests.all.contains("POST /api/v1/accounts none"))
  }

  @Test func logOutOfAnAlreadyDeletedAccountStartsAFreshOne() async throws {
    let store = InMemoryCredentialStore("ala_old")
    let model = accountModel(store: store, requests: Requests()) {
      (401, Data(json: #"{"error": {"code": "unauthorized", "message": "Unauthorized."}}"#))
    }
    await model.start()

    try await model.logOut()

    #expect(try store.load() == "ala_new")
    #expect(model.assistants.isEmpty)
  }
}
