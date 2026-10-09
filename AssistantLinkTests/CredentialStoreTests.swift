import Foundation
import Testing

@testable import AssistantLink

struct KeychainCredentialStoreTests {
  private let store = KeychainCredentialStore(
    service: "ai.assistantlink.tests.\(UUID().uuidString)", account: "https://service.test")

  @Test func loadsNothingBeforeSaving() throws {
    #expect(try store.load() == nil)
  }

  @Test func savesLoadsAndDeletes() throws {
    defer { try? store.delete() }

    try store.save("ala_first")
    #expect(try store.load() == "ala_first")

    try store.save("ala_second")
    #expect(try store.load() == "ala_second")

    try store.delete()
    #expect(try store.load() == nil)
  }

  @Test func keepsOneCredentialPerService() throws {
    let local = KeychainCredentialStore(service: store.service, account: "http://localhost:4000")
    defer {
      try? store.delete()
      try? local.delete()
    }

    try store.save("ala_production")
    #expect(try local.load() == nil)
  }

  @Test func deletingAMissingCredentialSucceeds() throws {
    try store.delete()
  }
}
