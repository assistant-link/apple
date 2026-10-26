import Foundation

extension Assistant {
  fileprivate static let hermesID = "01a11a4e-0771-7baf-8a8b-2f8f3f86e219"
  fileprivate static let museID = "01a11a4f-0000-7000-8000-000000000002"

  static let samples: [Assistant] = [
    Assistant(
      id: hermesID, name: "Hermes", avatar: "avatar-3",
      status: .online,
      links: [
        Link(
          id: "01a11a4e-0a6a-7edf-996d-7e8f06fc11ed", label: "laptop", status: .online,
          lastActiveAt: .now),
        Link(
          id: "01a11a4e-42ee-7ebf-b82d-d195d2252d57", label: "cloud", status: .offline,
          lastActiveAt: .now.addingTimeInterval(-7200)),
        Link(
          id: "01a11a5f-1c00-7a1b-9c2d-3e4f5a6b7c8d", label: nil, status: .notPaired,
          lastActiveAt: nil),
      ],
      latestEvent: Event.samples.last),
    Assistant(
      id: "01a11a4f-0000-7000-8000-000000000001", name: "Grok Bot", avatar: "avatar-6",
      status: .offline, links: []),
    Assistant(
      id: museID, name: "Muse", avatar: "avatar-1",
      status: .offline,
      links: [
        Link(
          id: "01a0f5c2-8000-7000-8000-000000000003", label: nil, status: .notPaired,
          lastActiveAt: nil)
      ],
      latestEvent: Event(
        id: "01a0f5c2-8000-7000-8000-000000000004", assistantID: museID, type: .linkCreated,
        sender: .system, createdAt: .now.addingTimeInterval(-86_400),
        linkID: "01a0f5c2-8000-7000-8000-000000000003")),
  ]

  /// The conversations opened in previews, by Assistant.
  static let sampleTimelines: [Assistant.ID: Timeline] = [
    hermesID: Timeline(events: Event.samples)
  ]
}

extension Event {
  /// Hermes' conversation, oldest first.
  static let samples: [Event] = [
    Event(
      id: "01a11a4e-0a6b-7000-8000-000000000001", assistantID: Assistant.hermesID,
      type: .linkCreated, sender: .system, createdAt: .now.addingTimeInterval(-7_200),
      linkID: "01a11a4e-0a6a-7edf-996d-7e8f06fc11ed"),
    Event(
      id: "01a11a4e-0a6b-7000-8000-000000000002", assistantID: Assistant.hermesID,
      type: .textMessage, sender: .user, createdAt: .now.addingTimeInterval(-3_600),
      deliveryStatus: .delivered, idempotencyKey: "01a11a4e-0a6b-7000-8000-0000000000a2",
      text: "Remind me to call David"),
    Event(
      id: "01a11a4e-0a6b-7000-8000-000000000003", assistantID: Assistant.hermesID,
      type: .textMessage, sender: .assistant, createdAt: .now.addingTimeInterval(-3_000),
      linkID: "01a11a4e-0a6a-7edf-996d-7e8f06fc11ed", text: "Done."),
  ]
}
