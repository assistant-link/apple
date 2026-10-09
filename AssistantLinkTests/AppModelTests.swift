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
