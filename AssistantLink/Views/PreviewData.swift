import Foundation

extension Assistant {
  static let samples: [Assistant] = [
    Assistant(
      id: "01a11a4e-0771-7baf-8a8b-2f8f3f86e219", name: "Hermes", avatar: "avatar-3",
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
      ]),
    Assistant(
      id: "01a11a4f-0000-7000-8000-000000000001", name: "Grok Bot", avatar: "avatar-6",
      status: .offline, links: []),
    Assistant(
      id: "01a11a4f-0000-7000-8000-000000000002", name: "Muse", avatar: "avatar-1",
      status: .offline,
      links: [
        Link(
          id: "01a0f5c2-8000-7000-8000-000000000003", label: nil, status: .notPaired,
          lastActiveAt: nil)
      ]),
  ]
}
