import SwiftUI

struct AssistantDetailsView: View {
  let assistantID: Assistant.ID

  @Environment(AppModel.self) private var model
  @State private var isCreatingLink = false
  @State private var pairingLink: Link?
  @State private var failure: Failure?

  private struct Failure {
    let title: String
    let message: String
  }

  var body: some View {
    if let assistant = model.assistant(id: assistantID) {
      details(assistant)
    } else {
      ContentUnavailableView("Assistant not found", systemImage: "questionmark.circle")
    }
  }

  private func details(_ assistant: Assistant) -> some View {
    List {
      Section {
        HStack(spacing: 16) {
          AvatarView(avatar: Avatar(id: assistant.avatar), size: 56)
          VStack(alignment: .leading, spacing: 4) {
            Text(assistant.name).font(.title2.bold())
            StatusBadge(assistant.status).foregroundStyle(.secondary)
          }
        }
      }

      Section {
        if assistant.links.isEmpty {
          Text("No Links yet. Add a Link to connect an agent to \(assistant.name).")
            .foregroundStyle(.secondary)
        }
        ForEach(Array(assistant.links.enumerated()), id: \.element.id) { position, link in
          if link.status == .notPaired {
            Button {
              pairingLink = link
            } label: {
              LinkRow(link: link, position: position, showsPairingHint: true)
            }
            .foregroundStyle(.primary)
          } else {
            LinkRow(link: link, position: position, showsPairingHint: false)
          }
        }
      } header: {
        Text("Links")
      }
    }
    .navigationTitle("Details")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if isCreatingLink {
          ProgressView()
        } else {
          Button("Add Link", systemImage: "plus") { addLink(to: assistant) }
        }
      }
    }
    .refreshable {
      do {
        try await model.refresh()
      } catch {
        failure = Failure(title: "Can't refresh", message: error.localizedDescription)
      }
    }
    .sheet(item: $pairingLink) { link in
      let position = assistant.links.firstIndex(of: link) ?? assistant.links.count
      PairingView(
        assistantName: assistant.name, linkID: link.id,
        linkName: link.displayName(position: position))
    }
    .alert(
      failure?.title ?? "", isPresented: .constant(failure != nil),
      actions: { Button("OK") { failure = nil } },
      message: { Text(failure?.message ?? "") })
  }

  private func addLink(to assistant: Assistant) {
    isCreatingLink = true
    Task {
      defer { isCreatingLink = false }
      do {
        pairingLink = try await model.createLink(assistantID: assistant.id)
      } catch {
        failure = Failure(title: "Can't add a Link", message: error.localizedDescription)
      }
    }
  }
}

private struct LinkRow: View {
  let link: Link
  let position: Int
  let showsPairingHint: Bool

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(link.displayName(position: position)).font(.headline)
        HStack(spacing: 6) {
          StatusBadge(link.status)
          Text("·")
          LastActiveText(lastActive: LastActive(link))
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        if let wake = WakeCaption(link) {
          WakeCaptionView(caption: wake)
        }
      }
      if showsPairingHint {
        Spacer()
        Text("Pair").foregroundStyle(.tint)
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 2)
  }
}

private struct WakeCaptionView: View {
  let caption: WakeCaption

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(caption.text)
        .foregroundStyle(caption.isMuted ? HierarchicalShapeStyle.tertiary : .secondary)
      if let note = caption.note {
        Text(note).foregroundStyle(.tertiary)
      }
    }
    .font(.footnote)
  }
}

#Preview("With Links") {
  NavigationStack {
    AssistantDetailsView(assistantID: Assistant.samples[0].id)
  }
  .environment(AppModel.preview(Assistant.samples))
}

#Preview("No Links") {
  NavigationStack {
    AssistantDetailsView(assistantID: Assistant.samples[1].id)
  }
  .environment(AppModel.preview(Assistant.samples))
}

#Preview("Woken by webhook") { WakeRoutePreview(wake: Wake.samples[0]) }
#Preview("Woken by email") { WakeRoutePreview(wake: Wake.samples[1]) }
#Preview("Woken by webhook, email also set") { WakeRoutePreview(wake: Wake.samples[2]) }
#Preview("Wake email pending") { WakeRoutePreview(wake: Wake.samples[3]) }
#Preview("No wake route") { WakeRoutePreview(wake: Wake.samples[4]) }

/// Hermes with only its laptop Link, as in the wake-route design mocks.
struct WakeRoutePreview: View {
  let wake: Wake

  var body: some View {
    let hermes = Assistant.hermesLaptop(wake: wake)
    NavigationStack {
      AssistantDetailsView(assistantID: hermes.id)
    }
    .environment(AppModel.preview([hermes]))
  }
}
