import SwiftUI

struct CreateAssistantView: View {
  var onCreate: (Assistant) -> Void = { _ in }

  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var hasEditedName = false
  @State private var avatar = Avatar.default
  @State private var isSaving = false
  @State private var error: String?

  private var validation: Result<String, TextValidation.Problem> { TextValidation.name(name) }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack(spacing: 12) {
            AvatarView(avatar: avatar, size: 44)
            TextField("Name", text: $name)
              .textInputAutocapitalization(.words)
              .submitLabel(.done)
              .onSubmit(save)
              .accessibilityIdentifier("assistantName")
          }
        } footer: {
          if hasEditedName, case .failure(let problem) = validation {
            Text(problem.message).foregroundStyle(.red)
          }
        }

        Section("Avatar") {
          AvatarPicker(selection: $avatar)
        }

        if let error {
          Section {
            Text(error).foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("New Assistant")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSaving {
            ProgressView()
          } else {
            Button("Create", action: save)
              .disabled((try? validation.get()) == nil)
          }
        }
      }
      .onChange(of: name) { hasEditedName = true }
      .interactiveDismissDisabled(isSaving)
    }
  }

  private func save() {
    guard case .success(let name) = validation, !isSaving else {
      hasEditedName = true
      return
    }
    isSaving = true
    error = nil
    Task {
      defer { isSaving = false }
      do {
        let assistant = try await model.createAssistant(name: name, avatar: avatar.id)
        dismiss()
        onCreate(assistant)
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

private struct AvatarPicker: View {
  @Binding var selection: Avatar

  var body: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
      ForEach(Avatar.presets) { avatar in
        Button {
          selection = avatar
        } label: {
          AvatarView(avatar: avatar, size: 40)
            .padding(5)
            .overlay {
              if avatar == selection {
                Circle().strokeBorder(Color.primary, lineWidth: 3)
              }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(avatar.name)
        .accessibilityIdentifier(avatar.id)
        .accessibilityAddTraits(avatar == selection ? .isSelected : [])
      }
    }
    .padding(.vertical, 8)
  }
}

#Preview {
  CreateAssistantView().environment(AppModel.preview([]))
}
