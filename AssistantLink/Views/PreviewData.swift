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

extension Timeline {
  /// The conversation of the 01-chat design mock, which ends with an answered request.
  static let designMock: Timeline = {
    let lines: [(Event.Sender, String, TimeInterval)] = [
      (.user, "Is my appointment still on for Friday?", -20_000),
      (.assistant, "Yes, it is confirmed for Friday at 8:30.", -19_900),
      (.user, "What is on my calendar tomorrow?", -19_800),
      (.assistant, "Nothing before noon. Enjoy the quiet morning.", -19_700),
      (
        .assistant, "Morning! You have three meetings today. The first is at 10:00 with Dana.",
        -9_000
      ),
      (.user, "Can you move my 2 pm meeting to 3?", -8_900),
      (.assistant, "Done. The meeting with the design team is now at 3 pm.", -8_800),
      (.user, "And add milk and eggs to the shopping list", -8_700),
      (.assistant, "Added both. Anything else?", -8_600),
    ]
    let events = lines.enumerated().map { index, line in
      Event(
        id: "01a11a4e-0a6b-7000-8000-\(String(format: "%012d", index + 100))",
        assistantID: Assistant.samples[0].id, type: .textMessage, sender: line.0,
        createdAt: .now.addingTimeInterval(line.2),
        deliveryStatus: line.0 == .user ? .delivered : nil, text: line.1)
    }
    return Timeline(events: events)
  }()
}

/// A voice chat that needs no microphone, for previews and the screenshot catalog.
@MainActor
private final class SilentVoice: SpeechListener, SpeechSpeaker, VoiceAudio, SilenceTimer {
  func start(_ handler: @escaping @MainActor (SpeechEvent) -> Void) throws {}
  func stop() {}
  func speak(_ text: String, onFinish: @escaping @MainActor () -> Void) {}
  func requestPermission() async -> Bool { true }
  func activate() throws {}
  func observeRouteChanges(_ handler: @escaping @MainActor () -> Void) {}
  func deactivate() {}
  func restart(_ fire: @escaping @MainActor () -> Void) {}
  func cancel() {}
}

extension VoiceCall {
  static func preview() -> VoiceCall {
    let voice = SilentVoice()
    return VoiceCall(listener: voice, speaker: voice, audio: voice, silence: voice)
  }
}

extension Timeline {
  /// The design mock followed by a 15 second voice chat.
  static let designMockAfterCall: Timeline = {
    var events = designMock.events
    let end = events.last?.createdAt ?? .now
    for (index, kind) in [Event.Kind.callStarted, .callEnded].enumerated() {
      events.append(
        Event(
          id: "01a11a4e-0a6b-7000-8000-\(String(format: "%012d", 200 + index))",
          assistantID: Assistant.samples[0].id, type: kind, sender: .system,
          createdAt: end.addingTimeInterval(60 + Double(index) * 15)))
    }
    return Timeline(events: events)
  }()
}
