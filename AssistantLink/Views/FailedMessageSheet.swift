import SwiftUI

extension View {
  /// Presents the Not Delivered options as a bottom sheet while `item` is set.
  func failedMessageSheet(
    item: Binding<OutgoingMessage?>,
    onTryAgain: @escaping (OutgoingMessage) -> Void,
    onCancel: @escaping (OutgoingMessage) -> Void
  ) -> some View {
    modifier(FailedMessageSheet(item: item, onTryAgain: onTryAgain, onCancel: onCancel))
  }
}

private struct FailedMessageSheet: ViewModifier {
  @Binding var item: OutgoingMessage?
  let onTryAgain: (OutgoingMessage) -> Void
  let onCancel: (OutgoingMessage) -> Void
  @State private var contentHeight: CGFloat = 200

  func body(content: Content) -> some View {
    content.sheet(item: $item) { message in
      FailedMessageOptions(
        onTryAgain: {
          item = nil
          onTryAgain(message)
        },
        onCancel: {
          item = nil
          onCancel(message)
        }
      )
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.height
      } action: { height in
        contentHeight = height
      }
      .presentationDetents([.height(contentHeight)])
      .presentationDragIndicator(.hidden)
      .presentationBackground(Color(.systemGroupedBackground))
    }
  }
}

private struct FailedMessageOptions: View {
  let onTryAgain: () -> Void
  let onCancel: () -> Void

  var body: some View {
    VStack(spacing: 8) {
      Text("Not Delivered")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 16)
        .padding(.bottom, 4)
      optionButton("Try Again", action: onTryAgain)
      optionButton("Cancel", action: onCancel)
    }
    .padding(.horizontal, 10)
    .padding(.bottom, 10)
  }

  private func optionButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 17))
        .foregroundStyle(.blue)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
  }
}
