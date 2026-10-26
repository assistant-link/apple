import SwiftUI

enum Route: Hashable {
  case conversation(Assistant.ID)
  case details(Assistant.ID)
}

struct AssistantListView: View {
  @Environment(AppModel.self) private var model
  @State private var path: [Route] = []
  @State private var isCreating = false
  @State private var refreshError: String?
  @State private var isConfirmingLogOut = false
  @State private var isConfirmingDeletion = false
  @State private var isLoggingOut = false
  @State private var logOutError: String?

  var body: some View {
    NavigationStack(path: $path) {
      content
        .navigationTitle("Assistants")
        .toolbar {
          if model.phase == .ready {
            ToolbarItem(placement: .primaryAction) {
              Button("New Assistant", systemImage: "plus") { isCreating = true }
            }
            ToolbarItem(placement: .topBarLeading) {
              if isLoggingOut {
                ProgressView()
              } else {
                Menu("More", systemImage: "ellipsis.circle") {
                  Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right") {
                    isConfirmingLogOut = true
                  }
                }
              }
            }
          }
        }
        .confirmationDialog(
          "Log out of Assistant Link?", isPresented: $isConfirmingLogOut, titleVisibility: .visible
        ) {
          Button("Log Out") { isConfirmingDeletion = true }
        }
        .alert("Delete everything?", isPresented: $isConfirmingDeletion) {
          Button("Delete Everything", role: .destructive) { logOut() }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(
            "Logging out permanently deletes all your Assistants, Assistant Links, and history. This can't be undone."
          )
        }
        .alert(
          "Can't log out", isPresented: .constant(logOutError != nil),
          actions: { Button("OK") { logOutError = nil } },
          message: { Text(logOutError ?? "") }
        )
        .navigationDestination(for: Route.self) { route in
          switch route {
          case .conversation(let id): ConversationView(assistantID: id)
          case .details(let id): AssistantDetailsView(assistantID: id)
          }
        }
        .sheet(isPresented: $isCreating) {
          CreateAssistantView { assistant in path.append(.conversation(assistant.id)) }
        }
        .alert(
          "Can't refresh", isPresented: .constant(refreshError != nil),
          actions: { Button("OK") { refreshError = nil } },
          message: { Text(refreshError ?? "") })
    }
  }

  private func logOut() {
    isLoggingOut = true
    Task {
      defer { isLoggingOut = false }
      do {
        try await model.logOut()
      } catch {
        logOutError = error.localizedDescription
      }
    }
  }

  @ViewBuilder private var content: some View {
    switch model.phase {
    case .loading:
      ProgressView("Connecting…")
    case .failed(let message):
      ContentUnavailableView {
        Label("Can't load Assistants", systemImage: "wifi.exclamationmark")
      } description: {
        Text(message)
      } actions: {
        Button("Try Again") { Task { await model.start() } }
      }
    case .ready where model.assistants.isEmpty:
      ContentUnavailableView {
        Label("No Assistants yet", systemImage: "person.crop.circle.badge.plus")
      } description: {
        Text("Create an Assistant, then link it to your agent.")
      } actions: {
        Button("Create Assistant") { isCreating = true }
          .buttonStyle(.borderedProminent)
      }
    case .ready:
      List(model.assistants) { assistant in
        NavigationLink(value: Route.conversation(assistant.id)) {
          AssistantRow(assistant: assistant)
        }
        .listRowSeparator(.hidden)
      }
      .listStyle(.plain)
      .refreshable {
        do {
          try await model.refresh()
        } catch {
          refreshError = error.localizedDescription
        }
      }
    }
  }
}

private struct AssistantRow: View {
  let assistant: Assistant

  var body: some View {
    HStack(spacing: 14) {
      AvatarView(
        avatar: Avatar(id: assistant.avatar), size: 52, isOnline: assistant.status == .online)
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(assistant.name)
            .font(.headline)
            .lineLimit(1)
          Spacer()
          if let date = assistant.latestEvent?.createdAt {
            Text(EventTime.short(date))
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        Text(preview)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
    .accessibilityValue(assistant.status == .online ? "Online" : "Offline")
  }

  private var preview: String {
    guard let event = assistant.latestEvent else { return "Set up a Link to connect your agent" }
    switch event.type {
    case .linkCreated:
      return "Assistant Link created"
    case .textMessage:
      let text = event.deleted ? "This message was deleted" : event.text ?? ""
      return event.sender == .user ? "You: \(text)" : text
    }
  }
}

#Preview("Assistants") {
  AssistantListView().environment(AppModel.preview(Assistant.samples))
}

#Preview("Empty") {
  AssistantListView().environment(AppModel.preview([]))
}
