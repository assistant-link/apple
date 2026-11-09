import XCTest

/// Captures each section of the component catalog; the names start with a number so the
/// screenshots job exports them.
final class ComponentScreenshotTests: XCTestCase {
  @MainActor func testCaptureComponents() {
    for (index, section) in ["messages", "composer", "call"].enumerated() {
      let app = XCUIApplication()
      app.launchArguments = ["-componentCatalog", section]
      app.launch()
      XCTAssertTrue(
        app.descendants(matching: .any)["componentCatalog"].waitForExistence(timeout: 30),
        "the \(section) catalog did not appear")
      // Lets the glass settle.
      Thread.sleep(forTimeInterval: 1)
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = "\(20 + index)-components-\(section)"
      attachment.lifetime = .keepAlways
      add(attachment)
      app.terminate()
    }
  }

  /// The chat screen of the design mocks 01-chat and 02-typing, on sample data.
  @MainActor func testCaptureChat() {
    let app = XCUIApplication()
    app.launchArguments = ["-componentCatalog", "chat"]
    app.launch()
    let field = app.descendants(matching: .any)["messageField"]
    XCTAssertTrue(field.waitForExistence(timeout: 30), "the chat did not appear")
    Thread.sleep(forTimeInterval: 1)
    capture(app, "30-chat")

    field.tap()
    field.typeText("Remind me to call David tomorrow at 9")
    Thread.sleep(forTimeInterval: 1)
    capture(app, "31-chat-typing")

    field.typeText(" and add it to my calendar so I do not forget about it")
    Thread.sleep(forTimeInterval: 1)
    capture(app, "33-chat-typing-long")
  }

  /// Design mocks 03-call-connecting, 04-call-live and 05-after-call, on sample data.
  @MainActor func testCaptureCall() {
    for (index, section) in ["call-connecting", "call-live", "after-call"].enumerated() {
      let app = XCUIApplication()
      app.launchArguments = ["-componentCatalog", section]
      app.launch()
      XCTAssertTrue(
        app.descendants(matching: .any)["messageField"].waitForExistence(timeout: 30),
        "the \(section) screen did not appear")
      if section != "after-call" {
        XCTAssertTrue(
          app.buttons["voiceEnd"].waitForExistence(timeout: 10), "the call did not start")
      }
      // The banner slides in and the timeline scrolls to keep the last message in view.
      Thread.sleep(forTimeInterval: 3)
      capture(app, "\(index + 40)-\(section)")
      app.terminate()
    }
  }

  /// The first-pairing screen of the design mock 06-first-pairing.
  @MainActor func testCaptureFirstPairing() {
    let app = XCUIApplication()
    app.launchArguments = ["-componentCatalog", "pairing"]
    app.launch()
    XCTAssertTrue(
      app.buttons["createLink"].waitForExistence(timeout: 30),
      "the first-pairing screen did not appear")
    Thread.sleep(forTimeInterval: 1)
    capture(app, "32-first-pairing")
  }

  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
