import Foundation
import SwiftUI
import Testing

@testable import AssistantLink

struct StatusTests {
  private func link(_ status: String) throws -> AssistantLink.Link {
    try APIClient.decoder.decode(
      AssistantLink.Link.self,
      from: Data(
        json: #"{"id": "l-1", "label": null, "status": "\#(status)", "last_active_at": null}"#))
  }

  private func assistant(_ status: String) throws -> Assistant {
    try APIClient.decoder.decode(
      Assistant.self,
      from: Data(
        json: #"""
          {"id": "as-1", "name": "Hermes", "avatar": "avatar-3", "status": "\#(status)",
           "links": []}
          """#))
  }

  @Test func decodesAnIdleLinkAndAssistant() throws {
    #expect(try link("idle").status == .idle)
    #expect(try assistant("idle").status == .idle)
  }

  @Test func unknownStatusesAreOffline() throws {
    #expect(try link("sleeping").status == .offline)
    #expect(try assistant("sleeping").status == .offline)
  }

  @Test func eachStatusHasItsLabelAndColor() {
    #expect(StatusBadge(AssistantLink.Link.Status.online).text == "Online")
    #expect(StatusBadge(AssistantLink.Link.Status.online).color == .green)
    #expect(StatusBadge(AssistantLink.Link.Status.idle).text == "Idle")
    #expect(StatusBadge(AssistantLink.Link.Status.idle).color == .yellow)
    #expect(StatusBadge(AssistantLink.Link.Status.offline).text == "Offline")
    #expect(StatusBadge(AssistantLink.Link.Status.offline).color == .gray)
    #expect(StatusBadge(AssistantLink.Link.Status.notPaired).text == "Not paired")
    #expect(StatusBadge(Assistant.Status.online).color == .green)
    #expect(StatusBadge(Assistant.Status.idle).text == "Idle")
    #expect(StatusBadge(Assistant.Status.idle).color == .yellow)
    #expect(StatusBadge(Assistant.Status.offline).color == .gray)
  }

  @Test func anAssistantIsAsAvailableAsItsMostAvailableLink() {
    #expect(Assistant.Status(links: [.offline, .idle, .online]) == .online)
    #expect(Assistant.Status(links: [.notPaired, .idle, .offline]) == .idle)
    #expect(Assistant.Status(links: [.notPaired, .offline]) == .offline)
    #expect(Assistant.Status(links: []) == .offline)
  }
}
