import Foundation
import Synchronization
import Testing

@testable import AssistantLink

final class InMemoryCredentialStore: CredentialStore {
  private let value: Mutex<String?>

  init(_ credential: String? = nil) { value = Mutex(credential) }

  func load() throws -> String? { value.withLock { $0 } }
  func save(_ credential: String) throws { value.withLock { $0 = credential } }
  func delete() throws { value.withLock { $0 = nil } }
}

struct AccountSessionTests {
  private let baseURL = URL(string: "https://service.test")!

  @Test func firstLaunchRegistersAndStoresTheCredential() async throws {
    let store = InMemoryCredentialStore()
    let registrations = Mutex(0)
    let session = StubURLProtocol.session { request, _ in
      #expect(request.url?.path() == "/api/v1/accounts")
      registrations.withLock { $0 += 1 }
      return (201, Data(json: #"{"account_id": "acc-1", "credential": "ala_new"}"#))
    }

    let api = try await AccountSession.connect(baseURL: baseURL, store: store, session: session)

    #expect(api.credential == "ala_new")
    #expect(try store.load() == "ala_new")
    #expect(registrations.withLock { $0 } == 1)
  }

  @Test func laterLaunchesReuseTheStoredCredential() async throws {
    let store = InMemoryCredentialStore("ala_existing")
    let session = StubURLProtocol.session { request, _ in
      Issue.record("unexpected request to \(request.url!)")
      return (500, Data())
    }

    let api = try await AccountSession.connect(baseURL: baseURL, store: store, session: session)

    #expect(api.credential == "ala_existing")
  }

  @Test func aFailedRegistrationStoresNothing() async throws {
    let store = InMemoryCredentialStore()
    let session = StubURLProtocol.session { _, _ in throw URLError(.timedOut) }

    await #expect(throws: APIError.unreachable) {
      try await AccountSession.connect(baseURL: baseURL, store: store, session: session)
    }
    #expect(try store.load() == nil)
  }
}
