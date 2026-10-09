import SwiftUI

struct ConversationView: View {
  let assistantID: Assistant.ID

  @Environment(AppModel.self) private var model
  @State private var pairingLink: Link?

  var body: some View {
    if let assistant = model.assistant(id: assistantID) {
      Group {
        if assistant.links.isEmpty {
          SetupGuideView(assistant: assistant) { pairingLink = $0 }
        } else {
          timeline(assistant)
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          NavigationLink(value: Route.details(assistant.id)) {
            TitleBubble(assistant: assistant)
          }
          .buttonStyle(.plain)
          .accessibilityHint("Shows the Assistant's details and Links")
        }
      }
      .sheet(item: $pairingLink) { link in
        PairingView(
          assistantName: assistant.name, linkID: link.id,
          linkName: link.displayName(position: assistant.links.firstIndex(of: link) ?? 0))
      }
    } else {
      ContentUnavailableView("Assistant not found", systemImage: "questionmark.circle")
    }
  }

  private func timeline(_ assistant: Assistant) -> some View {
    ScrollView {
      LazyVStack(spacing: 20) {
        ForEach(assistant.events) { event in
          SystemEventView(
            event: event,
            linkName: event.link.displayName(
              position: assistant.links.firstIndex(of: event.link) ?? 0)
          ) {
            pairingLink = event.link
          }
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 24)
    }
    .defaultScrollAnchor(.bottom)
    .refreshable { try? await model.refresh() }
  }
}

private struct TitleBubble: View {
  let assistant: Assistant

  var body: some View {
    HStack(spacing: 8) {
      AvatarView(
        avatar: Avatar(id: assistant.avatar), size: 28, isOnline: assistant.status == .online)
      VStack(alignment: .leading, spacing: 0) {
        Text(assistant.name)
          .font(.headline)
          .lineLimit(1)
        Text(assistant.status == .online ? "Online" : "Offline")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 6)
    .padding(.leading, 6)
    .padding(.trailing, 14)
    .modifier(BubbleBackground())
    .accessibilityElement(children: .combine)
  }
}

private struct BubbleBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(.regular.interactive(), in: .capsule)
    } else {
      content.background(.regularMaterial, in: Capsule())
    }
  }
}

private struct SystemEventView: View {
  let event: TimelineEvent
  let linkName: String
  let showPairingText: () -> Void

  var body: some View {
    VStack(spacing: 6) {
      if let date = event.date {
        Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
          .font(.footnote)
          .foregroundStyle(.tertiary)
      }
      Label("Assistant Link created", systemImage: "link")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Text(event.link.status == .notPaired ? "\(linkName) · not paired yet" : linkName)
        .font(.footnote)
        .foregroundStyle(.tertiary)
      if event.link.status == .notPaired {
        Button("Show pairing text", action: showPairingText)
          .font(.subheadline)
      }
    }
    .frame(maxWidth: .infinity)
    .multilineTextAlignment(.center)
  }
}

private struct SetupGuideView: View {
  let assistant: Assistant
  let onCreate: (Link) -> Void

  @Environment(AppModel.self) private var model
  @State private var isSaving = false
  @State private var error: String?

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        VStack(spacing: 12) {
          AvatarView(avatar: Avatar(id: assistant.avatar), size: 72)
          Text("Connect \(assistant.name) to your agent")
            .font(.title2.bold())
          Text(
            "An Assistant Link connects \(assistant.name) to the agent that runs it, on your computer or in the cloud."
          )
          .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)

        VStack(alignment: .leading, spacing: 20) {
          step(
            1, "Get the pairing text",
            "It holds a code that pairs your agent with \(assistant.name).")
          step(2, "Paste it to your agent", "It explains everything the agent needs to do.")
          step(3, "Your agent connects", "\(assistant.name) shows as online while it is connected.")
        }

        if let error {
          Text(error).font(.footnote).foregroundStyle(.red)
        }

        Button(action: create) {
          if isSaving {
            ProgressView().frame(maxWidth: .infinity)
          } else {
            Text("Get Pairing Text").frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isSaving)
        .accessibilityIdentifier("createLink")
      }
      .padding(24)
    }
  }

  private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text("\(number)")
        .font(.subheadline.bold())
        .foregroundStyle(.white)
        .frame(width: 24, height: 24)
        .background(Circle().fill(.tint))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(detail).font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }

  private func create() {
    guard !isSaving else { return }
    isSaving = true
    error = nil
    Task {
      defer { isSaving = false }
      do {
        onCreate(try await model.createLink(assistantID: assistant.id))
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

#Preview("Conversation") {
  NavigationStack {
    ConversationView(assistantID: Assistant.samples[0].id)
  }
  .environment(AppModel.preview(Assistant.samples))
}

#Preview("Setup guide") {
  NavigationStack {
    ConversationView(assistantID: Assistant.samples[1].id)
  }
  .environment(AppModel.preview(Assistant.samples))
}
