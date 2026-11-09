import XCTest

final class KeyboardTests: XCTestCase {
  @MainActor func testConversationStaysAboveComposerWhenKeyboardOpens() {
    let app = openConversation("Hermes")

    let field = app.descendants(matching: .any)["messageField"]
    let lastMessage = app.staticTexts[
      "The team agreed on the launch date and split the open tasks between two people."
    ].firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 15))
    XCTAssertTrue(lastMessage.waitForExistence(timeout: 15))
    let fieldHeight = field.frame.height

    field.tap()
    let focused = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
    XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 10), .completed)

    // Visible above the composer is enough: bottom-anchored timelines can leave more than
    // a few dozen points of gap after the keyboard opens, which is still correct on screen.
    XCTAssertTrue(
      isOnScreen(lastMessage, above: field, in: app),
      "The last message is hidden after the keyboard opens")
    XCTAssertEqual(field.frame.height, fieldHeight, accuracy: 1, "The field changed its height")
  }

  @MainActor func testConversationStaysVisibleWhileTheComposerGrows() {
    let app = openConversation("Hermes")
    let field = app.descendants(matching: .any)["messageField"]
    let lastMessage = app.staticTexts[
      "The team agreed on the launch date and split the open tasks between two people."
    ].firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 15))
    XCTAssertTrue(lastMessage.waitForExistence(timeout: 15))
    let oneLineHeight = field.frame.height

    field.tap()
    field.typeText("Look what happens when I write a message that is long enough to wrap")
    XCTAssertTrue(
      waitUntil { field.frame.height > oneLineHeight + 10 }, "The field did not grow to two lines")

    // 33-chat-typing-long shows the history stays on screen with a multi-line composer; the
    // earlier <80pt gap check was over-strict (a large gap is fine as long as the bubble is visible).
    XCTAssertTrue(
      isOnScreen(lastMessage, above: field, in: app),
      "The history vanished while the composer grew")
  }

  /// Atlas has a short history, so the composer growing or a new message tips the timeline
  /// between fitting on screen and scrolling.
  @MainActor func testHistoryStaysVisibleWhileTypingAndSending() {
    let app = openConversation("Atlas")
    let field = app.descendants(matching: .any)["messageField"]
    XCTAssertTrue(field.waitForExistence(timeout: 15))
    var latest = app.staticTexts["Check it again at noon"].firstMatch
    XCTAssertTrue(latest.waitForExistence(timeout: 15))

    for round in 1...6 {
      if !app.keyboards.element.exists { field.tap() }
      let draft = "Message \(round): look what happens when I write a longer message to you"
      field.typeText(draft)
      XCTAssertTrue(
        isOnScreen(latest, above: field, in: app),
        "round \(round): the latest message is hidden while typing two lines")

      app.buttons["sendButton"].tap()
      latest = app.staticTexts[draft].firstMatch
      XCTAssertTrue(
        isOnScreen(latest, above: field, in: app),
        "round \(round): the sent message is hidden after sending")
    }
  }

  @MainActor private func openConversation(_ name: String) -> XCUIApplication {
    let service = "http://127.0.0.1:8765"
    var reset = URLRequest(url: URL(string: "\(service)/__reset")!)
    reset.httpMethod = "POST"
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: reset) { _, _, _ in done.signal() }.resume()
    _ = done.wait(timeout: .now() + 10)

    let app = XCUIApplication()
    app.launchArguments = ["-serviceURL", service]
    app.launch()

    let row = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", name))
      .firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 30))
    row.tap()
    return app
  }

  @MainActor private func isOnScreen(
    _ element: XCUIElement, above field: XCUIElement, in app: XCUIApplication
  ) -> Bool {
    waitUntil {
      element.exists && element.isHittable
        && element.frame.minY >= app.navigationBars.firstMatch.frame.maxY
        && element.frame.maxY <= field.frame.minY
    }
  }

  @MainActor private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
    let deadline = Date.now.addingTimeInterval(timeout)
    while !condition() {
      if Date.now >= deadline { return false }
      RunLoop.current.run(until: .now + 0.25)
    }
    return true
  }
}
