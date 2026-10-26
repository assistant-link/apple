import SwiftUI

extension View {
  /// Presents the Not Delivered options as a bottom sheet while `item` is set.
  func failedMessageSheet(
    item: Binding<OutgoingMessage?>,
    onTryAgain: @escaping (OutgoingMessage) -> Void,
    onDelete: @escaping (OutgoingMessage) -> Void
  ) -> some View {
    modifier(FailedMessageSheet(item: item, onTryAgain: onTryAgain, onDelete: onDelete))
  }
}

private struct FailedMessageSheet: ViewModifier {
  @Binding var item: OutgoingMessage?
  let onTryAgain: (OutgoingMessage) -> Void
  let onDelete: (OutgoingMessage) -> Void
  @State private var contentHeight: CGFloat = 182
  /// The detent height includes the bottom safe area, which the measured content excludes.
  private let homeIndicatorHeight: CGFloat = 34

  func body(content: Content) -> some View {
    content.sheet(item: $item) { message in
      FailedMessageOptions(
        onTryAgain: {
          item = nil
          onTryAgain(message)
        },
        onDelete: {
          item = nil
          onDelete(message)
        },
        onClose: { item = nil }
      )
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.height
      } action: { height in
        contentHeight = height
      }
      .presentationDetents([.height(contentHeight + homeIndicatorHeight)])
      .presentationDragIndicator(.hidden)
      .presentationBackground(Color(.systemGroupedBackground))
    }
  }
}

private struct FailedMessageOptions: View {
  let onTryAgain: () -> Void
  let onDelete: () -> Void
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 8) {
      titleRow
      optionButton("Try Again", color: .blue, action: onTryAgain)
      optionButton("Delete Message", color: .red, action: onDelete)
    }
    .padding(.top, 10)
    .padding(.horizontal, 10)
    .padding(.bottom, 8)
  }

  private var titleRow: some View {
    ZStack {
      Text("Not Delivered")
        .font(.system(size: 17, weight: .semibold))
      HStack {
        Spacer()
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
      }
    }
    .frame(height: 44)
  }

  private func optionButton(
    _ title: String, color: Color, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 17))
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
          Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
  }
}
