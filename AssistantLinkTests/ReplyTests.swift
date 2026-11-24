import Foundation
import Testing

@testable import AssistantLink

struct ReplyTargetTests {
  private func message(
    _ id: String, _ sender: Event.Sender = .assistant, text: String? = nil, deleted: Bool = false,
    via: Event.Via? = nil
  ) -> Event {
    Event(
      id: id, assistantID: "as-1", type: .textMessage, sender: sender,
      createdAt: Date(timeIntervalSince1970: 0), deleted: deleted, idempotencyKey: "k-\(id)",
      text: deleted ? nil : (text ?? id), via: via)
  }

  private func call(_ id: String, _ type: Event.Kind) -> Event {
    Event(
      id: id, assistantID: "as-1", type: type, sender: .system,
      createdAt: Date(timeIntervalSince1970: 0))
  }

  private func targets(_ timeline: Timeline) -> [String: ReplyTarget?] {
    Dictionary(uniqueKeysWithValues: timeline.rows.map { ($0.id, $0.replyTarget) })
  }

  @Test func chatMessagesFromEitherSideCanBeRepliedTo() {
    let timeline = Timeline(events: [
      message("e-1", text: "Is Friday still good?"), message("e-2", .user, text: "Yes"),
    ])

    #expect(
      timeline.rows.map(\.replyTarget) == [
        ReplyTarget(eventID: "e-1", text: "Is Friday still good?", isFromUser: false),
        ReplyTarget(eventID: "e-2", text: "Yes", isFromUser: true),
      ])
  }

  @Test func theCallEntryAndItsUtterancesCannotBeRepliedTo() {
    let timeline = Timeline(events: [
      message("e-1"), call("e-2", .callStarted), message("e-3", .user, via: .voice),
      message("e-4"), call("e-5", .callEnded),
    ])

    let targets = targets(timeline)
    #expect(targets.keys.sorted() == ["e-2", "e-5", "k-e-1"])
    #expect(targets["e-2"] == .some(nil))
    #expect(targets["e-5"] == .some(nil))
    #expect(targets["k-e-1"] != .some(nil))
  }

  @Test func theUtterancesOfACallStillOnCannotBeRepliedTo() {
    let timeline = Timeline(events: [
      message("e-1"), call("e-2", .callStarted), message("e-3", .user, via: .voice),
      message("e-4", via: .voice),
    ])

    #expect(timeline.rows.map { $0.replyTarget != nil } == [true, false, false, false])
  }

  @Test func aCallThatNeverEndedLeavesLaterChatRepliable() {
    let timeline = Timeline(events: [
      call("e-1", .callStarted), message("e-2", .user, via: .voice),
      message("e-3", text: "Typed after the call dropped"), message("e-4", .user, text: "Thanks"),
    ])

    #expect(
      timeline.rows.map(\.replyTarget) == [
        nil, nil,
        ReplyTarget(eventID: "e-3", text: "Typed after the call dropped", isFromUser: false),
        ReplyTarget(eventID: "e-4", text: "Thanks", isFromUser: true),
      ])
  }

  @Test func deletedAndUnsentMessagesCannotBeRepliedTo() {
    let unsent = OutgoingMessage(
      assistantID: "as-1", idempotencyKey: "k-9", text: "Hi", createdAt: .now)
    let timeline = Timeline(
      events: [message("e-1", deleted: true), call("e-2", .linkCreated)], outgoing: [unsent])

    #expect(timeline.rows.map(\.replyTarget) == [nil, nil, nil])
  }

  @Test func theQuoteBarSaysWhoseMessageItAnswers() {
    let hermes = ReplyTarget(eventID: "e-1", text: "Is Friday still good?", isFromUser: false)
    let own = ReplyTarget(eventID: "e-2", text: "Yes", isFromUser: true)

    #expect(hermes.title(assistantName: "Hermes") == "Replying to Hermes")
    #expect(own.title(assistantName: "Hermes") == "Replying to you")
  }
}

struct ReplyQuoteTests {
  private func message(_ id: String, deleted: Bool = false) -> Event {
    Event(
      id: id, assistantID: "as-1", type: .textMessage, sender: .assistant,
      createdAt: Date(timeIntervalSince1970: 0), deleted: deleted, idempotencyKey: "k-\(id)",
      text: deleted ? nil : "Text of \(id)")
  }

  private func call(_ id: String, _ type: Event.Kind) -> Event {
    Event(
      id: id, assistantID: "as-1", type: type, sender: .system,
      createdAt: Date(timeIntervalSince1970: 0))
  }

  @Test func aLoadedOriginalIsQuotedAndScrolledToByItsRow() {
    let timeline = Timeline(events: [message("e-1"), message("e-2")])

    let quote = timeline.quote(forReplyTo: "e-1")

    #expect(quote == .message(text: "Text of e-1", rowID: "k-e-1"))
    #expect(quote?.text == "Text of e-1")
    #expect(quote?.isTappable == true)
  }

  @Test func aDeletedOriginalSaysSoAndDoesNothing() {
    let quote = Timeline(events: [message("e-1", deleted: true)]).quote(forReplyTo: "e-1")

    #expect(quote == .deleted)
    #expect(quote?.text == "This message was deleted")
    #expect(quote?.isTappable == false)
  }

  @Test func anOriginalBeforeTheLoadedPagesIsLoadedOnTap() {
    let quote = Timeline(events: [message("e-5")], hasMore: true).quote(forReplyTo: "e-1")

    #expect(quote == .earlier)
    #expect(quote?.isTappable == true)
  }

  @Test func anOriginalTheConversationDoesNotHaveIsNotQuoted() {
    #expect(Timeline(events: [message("e-5")]).quote(forReplyTo: "e-1") == nil)
    #expect(Timeline(events: [call("e-1", .callEnded)]).quote(forReplyTo: "e-1") == nil)
  }

  @Test func anOriginalSaidInAnEndedCallScrollsToTheCall() {
    let timeline = Timeline(events: [
      call("e-1", .callStarted), message("e-2"), call("e-3", .callEnded),
    ])

    #expect(timeline.quote(forReplyTo: "e-2") == .message(text: "Text of e-2", rowID: "e-3"))
  }
}

struct MessageDraftTests {
  private let target = ReplyTarget(eventID: "e-1", text: "Is Friday still good?", isFromUser: false)

  @Test func cancellingTheReplyKeepsTheDraft() {
    var draft = MessageDraft(text: "Yes, keep Friday.", replyTarget: target)

    draft.replyTarget = nil

    #expect(draft == MessageDraft(text: "Yes, keep Friday."))
  }

  @Test func sendingTakesTheReplyWithTheDraft() {
    var draft = MessageDraft(text: "Yes, keep Friday.", replyTarget: target)

    let sent = draft.take()

    #expect(sent.text == "Yes, keep Friday.")
    #expect(sent.replyTo == "e-1")
    #expect(draft == MessageDraft())
  }

  @Test func sendingWithoutAReplyAnswersNothing() {
    var draft = MessageDraft(text: "Hi")

    #expect(draft.take().replyTo == nil)
  }
}
