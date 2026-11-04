import SwiftUI

/// An Assistant with no Link yet; the button creates one and hands it to `onCreate`.
struct FirstPairingView: View {
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
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .font(.headline)
        .disabled(isSaving)
        .accessibilityIdentifier("createLink")
      }
      .padding(24)
    }
  }

  private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
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
