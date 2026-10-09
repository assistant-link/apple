import Foundation
import Testing

@testable import AssistantLink

struct LiveMessageTests {
  @Test func decodesAnOnlineLinkStatus() throws {
    let message = LiveMessage(
      text: #"""
        {"jsonrpc": "2.0", "method": "link.status",
         "params": {"link_id": "l-1", "status": "online",
                    "last_active_at": "2026-10-08T12:30:15.123456Z"}}
        """#)

    guard case .linkStatus(let change) = message else {
      Issue.record("expected link.status, got \(message)")
      return
    }
    #expect(change.linkID == "l-1")
    #expect(change.status == .online)
    let lastActive = try #require(change.lastActiveAt)
    #expect(abs(lastActive.timeIntervalSince1970 - 1_791_462_615.123456) < 0.001)
  }

  @Test func decodesAnOfflineLinkStatus() {
    let message = LiveMessage(
      text: #"""
        {"jsonrpc": "2.0", "method": "link.status",
         "params": {"link_id": "l-2", "status": "offline", "last_active_at": "2026-10-08T12:31:00Z"}}
        """#)

    #expect(
      message
        == .linkStatus(
          LinkStatusChange(
            linkID: "l-2", status: .offline,
            lastActiveAt: Date(timeIntervalSince1970: 1_791_462_660))))
  }

  @Test func ignoresUnknownFields() {
    let message = LiveMessage(
      text: #"""
        {"jsonrpc": "2.0", "method": "link.status", "extra": true,
         "params": {"link_id": "l-1", "status": "offline", "last_active_at": null, "new": 1}}
        """#)

    #expect(message == .linkStatus(LinkStatusChange(linkID: "l-1", status: .offline)))
  }

  @Test func decodesConnectionClosing() {
    let message = LiveMessage(
      text: #"""
        {"jsonrpc": "2.0", "method": "connection.closing", "params": {"reason": "account_deleted"}}
        """#)

    #expect(message == .closing(reason: "account_deleted"))
  }

  @Test(arguments: [
    #"{"jsonrpc": "2.0", "method": "message.new", "params": {"id": "m-1"}}"#,
    #"{"jsonrpc": "2.0", "id": 1, "result": {}}"#,
    #"{"jsonrpc": "2.0", "id": null, "error": {"code": -32600, "message": "Invalid Request"}}"#,
    #"{"jsonrpc": "2.0", "method": "link.status", "params": {"link_id": "l-1"}}"#,
    #"{"jsonrpc": "1.0", "method": "connection.closing", "params": {"reason": "x"}}"#,
    #"[{"jsonrpc": "2.0", "method": "link.status"}]"#,
    "not json",
  ])
  func ignoresEverythingElse(text: String) {
    #expect(LiveMessage(text: text) == .ignored)
  }
}

extension LinkStatusChange {
  init(linkID: String, status: Link.Status) {
    self.init(linkID: linkID, status: status, lastActiveAt: nil)
  }
}
