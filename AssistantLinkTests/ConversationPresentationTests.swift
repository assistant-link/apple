import Foundation
import Testing

@testable import AssistantLink

struct ConversationPresentationTests {
  private func assistant(status: Assistant.Status, links: [Link.Status]) -> Assistant {
    Assistant(
      id: "a-1", name: "Hermes", avatar: "avatar-1", status: status,
      links: links.enumerated().map {
        Link(id: "l-\($0.offset)", label: nil, status: $0.element, lastActiveAt: nil)
      })
  }

  private func message(
    sender: Event.Sender = .user, text: String? = "Hi", deleted: Bool = false
  ) -> Event {
    Event(
      id: "e-1", assistantID: "a-1", type: .textMessage, sender: sender, createdAt: .now,
      deleted: deleted, text: text)
  }

  @Test func composerShowsOnlyWithAPairedLink() {
    #expect(assistant(status: .online, links: [.online]).hasPairedLink)
    #expect(assistant(status: .offline, links: [.notPaired, .offline]).hasPairedLink)
    #expect(!assistant(status: .offline, links: [.notPaired]).hasPairedLink)
    #expect(!assistant(status: .offline, links: []).hasPairedLink)
  }

  @Test func offlineNoticeNamesTheAssistant() {
    #expect(
      assistant(status: .offline, links: [.offline]).offlineNotice
        == "Hermes is offline. Messages will be delivered when it connects.")
  }

  @Test func noOfflineNoticeWhileOnlineOrWithoutAPairedLink() {
    #expect(assistant(status: .online, links: [.online]).offlineNotice == nil)
    #expect(assistant(status: .offline, links: [.notPaired]).offlineNotice == nil)
    #expect(assistant(status: .offline, links: []).offlineNotice == nil)
  }

  @Test func previewPrefixesTheUsersMessages() {
    #expect(ListPreview(event: message(), failedMessage: nil).text == "You: Hi")
    #expect(ListPreview(event: message(sender: .assistant), failedMessage: nil).text == "Hi")
  }

  @Test func previewOfADeletedMessage() {
    let deleted = message(text: nil, deleted: true)
    let mine = ListPreview(event: deleted, failedMessage: nil)
    #expect(mine.text == "You: This message was deleted")
    let theirs = message(sender: .assistant, text: nil, deleted: true)
    #expect(ListPreview(event: theirs, failedMessage: nil).text == "This message was deleted")
  }

  @Test func previewOfALinkCreatedEvent() {
    let event = Event(
      id: "e-2", assistantID: "a-1", type: .linkCreated, sender: .system, createdAt: .now,
      linkID: "l-0")
    #expect(ListPreview(event: event, failedMessage: nil).text == "Assistant Link created")
  }

  @Test func previewWithoutEventsInvitesToSetUp() {
    let preview = ListPreview(event: nil, failedMessage: nil)
    #expect(preview.text == "Set up a Link to connect your agent")
    #expect(!preview.isFailed)
  }

  @Test func previewOfAFailedMessageIsMarked() {
    let failed = OutgoingMessage(
      assistantID: "a-1", idempotencyKey: "k-1", text: "Oops", createdAt: .now, state: .failed)
    let preview = ListPreview(event: message(), failedMessage: failed)
    #expect(preview == ListPreview(event: nil, failedMessage: failed))
    #expect(preview.text == "You: Oops")
    #expect(preview.isFailed)
  }
}
