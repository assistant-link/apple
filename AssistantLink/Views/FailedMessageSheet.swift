import SwiftUI
import UIKit

extension View {
  /// Presents the Not Delivered action sheet while `item` is set and clears it when any button is
  /// pressed. SwiftUI's `confirmationDialog` renders as a popover on iOS 26, so this uses UIKit.
  func failedMessageSheet(
    item: Binding<OutgoingMessage?>,
    onTryAgain: @escaping (OutgoingMessage) -> Void,
    onCancelMessage: @escaping (OutgoingMessage) -> Void
  ) -> some View {
    modifier(
      FailedMessageSheet(item: item, onTryAgain: onTryAgain, onCancelMessage: onCancelMessage))
  }
}

private struct FailedMessageSheet: ViewModifier {
  @Binding var item: OutgoingMessage?
  let onTryAgain: (OutgoingMessage) -> Void
  let onCancelMessage: (OutgoingMessage) -> Void

  func body(content: Content) -> some View {
    content.onChange(of: item?.id) {
      if let message = item { present(message) }
    }
  }

  private func present(_ message: OutgoingMessage) {
    // With the keyboard up, the sheet floated above it instead of sitting at the bottom.
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(350))
      guard item?.id == message.id else { return }
      presentSheet(for: message)
    }
  }

  private func presentSheet(for message: OutgoingMessage) {
    guard let top = Self.topViewController() else {
      item = nil
      return
    }
    let sheet = UIAlertController(
      title: "Not Delivered", message: nil, preferredStyle: .actionSheet)
    sheet.addAction(
      UIAlertAction(title: "Try Again", style: .default) { _ in
        item = nil
        onTryAgain(message)
      })
    sheet.addAction(
      UIAlertAction(title: "Cancel Message", style: .destructive) { _ in
        item = nil
        onCancelMessage(message)
      })
    sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in item = nil })
    top.present(sheet, animated: true)
  }

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
