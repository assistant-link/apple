import XCTest

final class ScreenshotTests: XCTestCase {
  private static let service = "http://127.0.0.1:8765"

  @MainActor func testCaptureKeyScreens() {
    continueAfterFailure = false
    addTeardownBlock { @MainActor [self] in
      guard (testRun?.totalFailureCount ?? 0) > 0 else { return }
      let app = XCUIApplication()
      capture(app, "0-failure")
      let hierarchy = XCTAttachment(string: String(app.debugDescription.prefix(3000)))
      hierarchy.name = "99-hierarchy"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
    }
    Self.resetService()
    let app = XCUIApplication()
    app.launchArguments = ["-serviceURL", Self.service]
    app.launch()

    expect(row("Hermes", in: app), "step 1: Hermes row exists", timeout: 30)
    expect(row("Atlas", in: app), "step 1: Atlas row exists")
    capture(app, "1-list")

    row("Hermes", in: app).tap()
    expect(app.messageField, "step 2: message field exists")
    expect(app.staticTexts["Delivered"], "step 2: Delivered caption exists")
    capture(app, "2-hermes")

    scrollToTop(app) { app.buttons["loadEarlier"].isHittable }
    XCTAssertTrue(
      app.buttons["loadEarlier"].isHittable, failure("step 4: Load Earlier button is hittable"))
    capture(app, "4-load-earlier")

    app.buttons["loadEarlier"].tap()
    expectGone(app.buttons["loadEarlier"], "step 5: Load Earlier button is gone")
    let created = app.staticTexts.matching(
      NSPredicate(format: "label == %@", "Assistant Link created")
    ).firstMatch
    scrollToTop(app) { created.isHittable }
    XCTAssertTrue(created.isHittable, failure("step 5: Assistant Link created text is hittable"))
    capture(app, "5-earlier-loaded")

    send("Can you check my flight status?", in: app)
    expect(app.staticTexts["Sent"], "step 6: Sent caption exists")
    capture(app, "6-sent")

    send("slow cooker recipes for dinner", in: app)
    expect(app.staticTexts["Sending…"], "step 7: Sending caption exists")
    capture(app, "7-sending")
    expectGone(app.staticTexts["Sending…"], "step 7: Sending caption is gone", timeout: 30)

    send("failover plan for the database", in: app)
    expect(app.staticTexts["Not Delivered"], "step 8: Not Delivered caption exists", timeout: 30)
    expect(app.failedMessage, "step 8: failed message button exists")
    capture(app, "8-not-delivered")

    tapWhenHittable(app.failedMessage, "step 9: failed message button")
    if !dialogButton("Try Again", in: app).waitForExistence(timeout: 5) {
      tapWhenHittable(
        app.staticTexts["failover plan for the database"], "step 9: failed message text")
    }
    expect(dialogButton("Try Again", in: app), "step 9: Try Again button exists")
    expect(dialogButton("Delete Message", in: app), "step 9: Delete Message button exists")
    expect(dialogButton("Close", in: app), "step 9: Close button exists")
    capture(app, "9-try-again-cancel")
    tapWhenHittable(dialogButton("Delete Message", in: app), "step 9: Delete Message button")
    expectGone(app.failedMessage, "step 9: failed message is gone after Delete Message")

    backButton(in: app).tap()
    expect(
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "label CONTAINS %@", "You: slow cooker recipes"))
        .firstMatch, "step 12: list preview of the last message exists")
    capture(app, "12-list-after-send")

    row("Grok Bot", in: app).tap()
    expect(backButton(in: app), "step 3: back button exists", timeout: 10)
    expect(app.buttons["createLink"], "step 3: Create Link button exists", timeout: 10)
    capture(app, "3-grok-bot-setup")

    backButton(in: app).tap()
    expect(row("Atlas", in: app), "step 10: Atlas row exists", timeout: 10)
    row("Atlas", in: app).tap()
    expect(app.messageField, "step 10: message field exists")
    expect(app.offlineNotice, "step 10: offline notice exists")
    XCTAssertTrue(app.messageField.isEnabled, failure("step 10: message field is enabled"))
    capture(app, "10-offline")

    backButton(in: app).tap()
    expect(row("Muse", in: app), "step 11: Muse row exists", timeout: 10)
    row("Muse", in: app).tap()
    expect(app.buttons["Show pairing text"], "step 11: Show pairing text button exists")
    XCTAssertFalse(app.messageField.exists, failure("step 11: message field does not exist"))
    capture(app, "11-no-composer")
  }

  @MainActor private func row(_ name: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", name))
      .firstMatch
  }

  @MainActor private func dialogButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons[label]
  }

  /// Adds the start of the view hierarchy, which the CI summary does not otherwise show.
  @MainActor private func failure(_ what: String) -> String {
    "\(what)\n\(XCUIApplication().debugDescription.prefix(1500))"
  }

  @MainActor private func expect(
    _ element: XCUIElement, _ what: String, timeout: TimeInterval = 15
  ) {
    XCTAssertTrue(element.waitForExistence(timeout: timeout), failure(what))
  }

  @MainActor private func expectGone(
    _ element: XCUIElement, _ what: String, timeout: TimeInterval = 15
  ) {
    XCTAssertTrue(waitUntil(element, "exists == false", timeout: timeout), failure(what))
  }

  @MainActor private func tapWhenHittable(_ element: XCUIElement, _ what: String) {
    expect(element, "\(what) exists")
    XCTAssertTrue(
      waitUntil(element, "isHittable == true", timeout: 15), failure("\(what) is hittable"))
    element.tap()
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
    expect(field, "send \"\(text)\": message field exists")
    var focused = false
    for _ in 0..<3 where !focused {
      field.tap()
      focused = waitUntil(field, "hasKeyboardFocus == true", timeout: 5)
    }
    XCTAssertTrue(focused, failure("send \"\(text)\": message field has keyboard focus"))
    field.typeText(text)
    let button = app.buttons["sendButton"]
    XCTAssertTrue(
      waitUntil(button, "isEnabled == true", timeout: 15),
      failure("send \"\(text)\": send button is enabled"))
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
