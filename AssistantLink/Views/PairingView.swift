import SwiftUI
import UIKit

struct PairingView: View {
  let assistantName: String
  let linkID: Link.ID
  let linkName: String

  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var pairing: PairingCode?
  @State private var error: String?
  @State private var isLoading = false
  @State private var copies = 0

  var body: some View {
    NavigationStack {
      Group {
        if let pairing {
          content(pairing)
        } else if let error {
          ContentUnavailableView {
            Label("Can't get a pairing code", systemImage: "exclamationmark.triangle")
          } description: {
            Text(error)
          } actions: {
            Button("Try Again") { Task { await load(renew: false) } }
          }
        } else {
          ProgressView()
        }
      }
      .navigationTitle("Pair \(linkName)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .task { await load(renew: false) }
    }
  }

  private func content(_ pairing: PairingCode) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(
          "Paste this to your agent. It tells the agent how to install Assistant Link’s tool and pair it with \(assistantName)."
        )
        .foregroundStyle(.secondary)

        Text(pairing.pairingText.trimmingCharacters(in: .newlines))
          .font(.callout.monospaced())
          .textSelection(.enabled)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
          .accessibilityIdentifier("pairingText")

        TimelineView(.periodic(from: .now, by: 1)) { context in
          let isExpired = context.date >= pairing.expiresAt
          VStack(alignment: .leading, spacing: 20) {
            if isExpired {
              Label("This code has expired. Get a new code.", systemImage: "clock.badge.xmark")
                .foregroundStyle(.red)
            } else {
              Label {
                Text(
                  "Code \(pairing.code) expires at \(pairing.expiresAt.formatted(date: .omitted, time: .shortened)) (\(Text(timerInterval: context.date...pairing.expiresAt, countsDown: true)) left)."
                )
              } icon: {
                Image(systemName: "clock")
              }
              .foregroundStyle(.secondary)
            }

            Button {
              UIPasteboard.general.string = pairing.pairingText
              copies += 1
            } label: {
              Label(
                copies > 0 ? "Copied" : "Copy Pairing Text",
                systemImage: copies > 0 ? "checkmark" : "doc.on.doc"
              )
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isExpired)
            .sensoryFeedback(.success, trigger: copies)
            .accessibilityIdentifier("copyPairingText")
          }
        }

        Button {
          Task { await load(renew: true) }
        } label: {
          Label("New Code", systemImage: "arrow.clockwise")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isLoading)

        Text("A new code replaces this one, so an agent that hasn’t paired yet needs the new text.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .padding()
    }
  }

  private func load(renew: Bool) async {
    isLoading = true
    defer { isLoading = false }
    do {
      pairing = try await model.pairingCode(linkID: linkID, renew: renew)
      copies = 0
      error = nil
    } catch {
      pairing = nil
      self.error = error.localizedDescription
      if case APIError.service(_, "already_paired", _) = error {
        try? await model.refresh()
      }
    }
  }
}
