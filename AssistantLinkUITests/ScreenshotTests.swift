import XCTest

final class ScreenshotTests: XCTestCase {
  private static let service = "http://127.0.0.1:8765"

  @MainActor func testCaptureKeyScreens() {
    continueAfterFailure = false
    Self.resetService()
    let app = XCUIApplication()
    app.launchArguments = ["-serviceURL", Self.service]
    app.launch()

    XCTAssertTrue(row("Hermes", in: app).waitForExistence(timeout: 30))
    XCTAssertTrue(row("Atlas", in: app).waitForExistence(timeout: 15))
    capture(app, "1-list")

    row("Hermes", in: app).tap()
    XCTAssertTrue(app.messageField.waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["Delivered"].waitForExistence(timeout: 15))
    capture(app, "2-hermes")

    scrollToTop(app) { app.buttons["loadEarlier"].isHittable }
    XCTAssertTrue(app.buttons["loadEarlier"].isHittable)
    capture(app, "4-load-earlier")

    app.buttons["loadEarlier"].tap()
    XCTAssertTrue(waitUntil(app.buttons["loadEarlier"], "exists == false", timeout: 15))
    scrollToTop(app) { app.staticTexts["Assistant Link created"].isHittable }
    XCTAssertTrue(app.staticTexts["Assistant Link created"].isHittable)
    capture(app, "5-earlier-loaded")

    send("Can you check my flight status?", in: app)
    XCTAssertTrue(app.staticTexts["Sent"].waitForExistence(timeout: 15))
    capture(app, "6-sent")

    send("slow cooker recipes for dinner", in: app)
    XCTAssertTrue(app.staticTexts["Sending…"].waitForExistence(timeout: 15))
    capture(app, "7-sending")
    XCTAssertTrue(waitUntil(app.staticTexts["Sending…"], "exists == false", timeout: 30))

    send("failover plan for the database", in: app)
    XCTAssertTrue(app.staticTexts["Not Delivered"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.failedMessage.waitForExistence(timeout: 15))
    capture(app, "8-not-delivered")

    app.failedMessage.tap()
    XCTAssertTrue(app.buttons["tryAgain"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["cancelSend"].waitForExistence(timeout: 15))
    capture(app, "9-try-again-cancel")
    app.buttons["cancelSend"].tap()
    XCTAssertTrue(waitUntil(app.failedMessage, "exists == false", timeout: 15))

    backButton(in: app).tap()
    XCTAssertTrue(
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "label CONTAINS %@", "You: slow cooker recipes"))
        .firstMatch.waitForExistence(timeout: 15))
    capture(app, "12-list-after-send")

    row("Grok Bot", in: app).tap()
    XCTAssertTrue(backButton(in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["createLink"].waitForExistence(timeout: 10))
    capture(app, "3-grok-bot-setup")

    backButton(in: app).tap()
    XCTAssertTrue(row("Atlas", in: app).waitForExistence(timeout: 10))
    row("Atlas", in: app).tap()
    XCTAssertTrue(app.messageField.waitForExistence(timeout: 15))
    XCTAssertTrue(app.offlineNotice.waitForExistence(timeout: 15))
    XCTAssertTrue(app.messageField.isEnabled)
    capture(app, "10-offline")

    backButton(in: app).tap()
    XCTAssertTrue(row("Muse", in: app).waitForExistence(timeout: 10))
    row("Muse", in: app).tap()
    XCTAssertTrue(app.buttons["Show pairing text"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.messageField.exists)
    capture(app, "11-no-composer")
  }

  @MainActor private func row(_ name: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", name))
      .firstMatch
  }

  @MainActor private func backButton(in app: XCUIApplication) -> XCUIElement {
    app.navigationBars.buttons.element(boundBy: 0)
  }

  @MainActor private func scrollToTop(
    _ app: XCUIApplication, until reached: @MainActor () -> Bool
  ) {
    for _ in 0..<20 where !reached() {
      app.swipeDown(velocity: .fast)
    }
  }

  @MainActor private func send(_ text: String, in app: XCUIApplication) {
    let field = app.messageField
    XCTAssertTrue(field.waitForExistence(timeout: 15))
    var focused = false
    for _ in 0..<3 where !focused {
      field.tap()
      focused = waitUntil(field, "hasKeyboardFocus == true", timeout: 5)
    }
    XCTAssertTrue(focused)
    field.typeText(text)
    let button = app.buttons["sendButton"]
    XCTAssertTrue(waitUntil(button, "isEnabled == true", timeout: 15))
    button.tap()
  }

  @MainActor private func waitUntil(
    _ element: XCUIElement, _ format: String, timeout: TimeInterval
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: format), object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

  @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// The mock keeps state, and the test runs once per appearance against the same process.
  private static func resetService() {
    var request = URLRequest(url: URL(string: "\(service)/__reset")!)
    request.httpMethod = "POST"
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
    _ = done.wait(timeout: .now() + 10)
  }
}

extension XCUIApplication {
  fileprivate var messageField: XCUIElement { descendants(matching: .any)["messageField"] }
  fileprivate var failedMessage: XCUIElement { descendants(matching: .any)["failedMessage"] }
  fileprivate var offlineNotice: XCUIElement { descendants(matching: .any)["offlineNotice"] }
}
