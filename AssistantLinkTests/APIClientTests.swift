import Foundation
import Testing

@testable import AssistantLink

struct APIClientTests {
  private let baseURL = URL(string: "https://service.test")!

  private func client(
    credential: String? = "ala_secret", _ handler: @escaping StubURLProtocol.Handler
  )
    -> APIClient
  {
    APIClient(baseURL: baseURL, credential: credential, session: StubURLProtocol.session(handler))
  }

  @Test func registerPostsWithoutACredential() async throws {
    let api = client(credential: nil) { request, _ in
      #expect(request.httpMethod == "POST")
      #expect(request.url?.absoluteString == "https://service.test/api/v1/accounts")
      #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
      return (201, Data(json: #"{"account_id": "acc-1", "credential": "ala_new"}"#))
    }

    let registration = try await api.register()

    #expect(registration == Registration(accountID: "acc-1", credential: "ala_new"))
  }

  @Test func listAssistantsSendsTheCredentialAndDecodesLinks() async throws {
    let api = client { request, _ in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.path() == "/api/v1/assistants")
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ala_secret")
      return (
        200,
        Data(
          json: #"""
            {"assistants": [{
              "id": "as-1", "name": "Hermes", "avatar": "avatar-3", "status": "online",
              "links": [
                {"id": "l-1", "label": "laptop", "status": "online",
                 "last_active_at": "2026-10-08T12:30:15.123456Z"},
                {"id": "l-2", "label": null, "status": "not_paired", "last_active_at": null}
              ]
            }]}
            """#)
      )
    }

    let assistants = try await api.listAssistants()

    let hermes = try #require(assistants.first)
    #expect(hermes.name == "Hermes")
    #expect(hermes.avatar == "avatar-3")
    #expect(hermes.status == .online)
    #expect(hermes.links.map(\.status) == [.online, .notPaired])
    #expect(hermes.links[0].label == "laptop")
    #expect(hermes.links[1].label == nil)
    #expect(hermes.links[1].lastActiveAt == nil)
    let lastActive = try #require(hermes.links[0].lastActiveAt)
    #expect(abs(lastActive.timeIntervalSince1970 - 1_791_462_615.123456) < 0.001)
  }

  @Test func createAssistantPostsNameAndAvatar() async throws {
    let api = client { request, body in
      #expect(request.httpMethod == "POST")
      #expect(request.url?.path() == "/api/v1/assistants")
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
      let json = try #require(try body?.jsonObject())
      #expect(json["name"] as? String == "Hermes")
      #expect(json["avatar"] as? String == "avatar-3")
      return (
        201,
        Data(
          json: #"""
            {"assistant": {"id": "as-1", "name": "Hermes", "avatar": "avatar-3",
                           "status": "offline", "links": []}}
            """#)
      )
    }

    let assistant = try await api.createAssistant(name: "Hermes", avatar: "avatar-3")

    #expect(assistant.id == "as-1")
    #expect(assistant.status == .offline)
    #expect(assistant.links.isEmpty)
  }

  @Test func createLinkPostsWithoutALabel() async throws {
    let api = client { request, body in
      #expect(request.httpMethod == "POST")
      #expect(request.url?.path() == "/api/v1/assistants/as-1/links")
      let json = try body?.jsonObject()
      #expect(json?.isEmpty == true)
      return (
        201,
        Data(
          json: #"""
            {"link": {"id": "l-1", "label": null, "status": "not_paired", "last_active_at": null}}
            """#)
      )
    }

    let link = try await api.createLink(assistantID: "as-1")

    #expect(link == Link(id: "l-1", label: nil, status: .notPaired, lastActiveAt: nil))
  }

  @Test func issuePairingCodeDecodesTheCodeExpiryAndText() async throws {
    let text = "Connect to my assistant \"Hermes\" on Assistant Link.\n"
    let api = client { request, _ in
      #expect(request.httpMethod == "POST")
      #expect(request.url?.path() == "/api/v1/links/l-1/pairing_code")
      return (
        201,
        Data(
          json: #"""
            {"code": "K7QM-2XPA", "expires_at": "2026-10-08T14:32:00.000000Z",
             "pairing_text": "Connect to my assistant \"Hermes\" on Assistant Link.\n"}
            """#)
      )
    }

    let pairing = try await api.issuePairingCode(linkID: "l-1")

    #expect(pairing.code == "K7QM-2XPA")
    #expect(pairing.pairingText == text)
    #expect(pairing.expiresAt == Date(timeIntervalSince1970: 1_791_469_920))
  }

  @Test func deleteAccountSendsDeleteWithTheCredential() async throws {
    let api = client { request, _ in
      #expect(request.httpMethod == "DELETE")
      #expect(request.url?.path() == "/api/v1/account")
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ala_secret")
      return (204, Data())
    }

    try await api.deleteAccount()
  }

  @Test func liveConnectionRequestUsesWebSocketSchemesAndTheCredential() throws {
    let secure = APIClient(baseURL: baseURL, credential: "ala_secret")
    let local = APIClient(baseURL: URL(string: "http://localhost:4000")!, credential: "ala_secret")

    let request = try #require(secure.liveConnectionRequest())

    #expect(request.url?.absoluteString == "wss://service.test/api/v1/connect")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ala_secret")
    #expect(
      local.liveConnectionRequest()?.url?.absoluteString == "ws://localhost:4000/api/v1/connect")
    #expect(APIClient(baseURL: baseURL, credential: nil).liveConnectionRequest() == nil)
  }

  @Test func serviceErrorsCarryTheCodeAndMessage() async throws {
    let api = client { _, _ in
      (422, Data(json: #"{"error": {"code": "invalid_params", "message": "name can't be blank"}}"#))
    }

    await #expect(
      throws: APIError.service(status: 422, code: "invalid_params", message: "name can't be blank")
    ) {
      try await api.createAssistant(name: "", avatar: "avatar-1")
    }
  }

  @Test func unauthorizedIsAServiceError() async throws {
    let api = client { _, _ in
      (401, Data(json: #"{"error": {"code": "unauthorized", "message": "Unauthorized."}}"#))
    }

    await #expect(
      throws: APIError.service(status: 401, code: "unauthorized", message: "Unauthorized.")
    ) {
      try await api.listAssistants()
    }
  }

  @Test func aResponseWithoutAnErrorBodyIsUnexpected() async throws {
    let api = client { _, _ in (502, Data("Bad Gateway".utf8)) }

    await #expect(throws: APIError.unexpectedResponse(status: 502)) {
      try await api.listAssistants()
    }
  }

  @Test func transportFailuresAreReported() async throws {
    let api = client { _, _ in throw URLError(.notConnectedToInternet) }

    await #expect(throws: APIError.unreachable) {
      try await api.listAssistants()
    }
  }
}
