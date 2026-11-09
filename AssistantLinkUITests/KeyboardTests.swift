import XCTest

final class KeyboardTests: XCTestCase {
  @MainActor func testConversationStaysAboveComposerWhenKeyboardOpens() {
    let app = openHermes()

    let field = app.descendants(matching: .any)["messageField"]
    let lastMessage = app.staticTexts[
      "The team agreed on the launch date and split the open tasks between two people."]
    XCTAssertTrue(field.waitForExistence(timeout: 15))
    XCTAssertTrue(lastMessage.waitForExistence(timeout: 15))
    let fieldHeight = field.frame.height

    field.tap()
    let focused = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
    XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 10), .completed)

    // The bubble sits 24 points of list padding and 8 of composer padding above the field.
    let isAboveComposer = waitUntil {
      lastMessage.exists && lastMessage.frame.maxY <= field.frame.minY
        && field.frame.minY - lastMessage.frame.maxY < 80
    }
    XCTAssertTrue(isAboveComposer, "The last message is hidden or far above the composer")
    XCTAssertEqual(field.frame.height, fieldHeight, accuracy: 1, "The field changed its height")
  }

  @MainActor func testConversationStaysVisibleWhileTheComposerGrows() {
    let app = openHermes()
    let field = app.descendants(matching: .any)["messageField"]
    let lastMessage = app.staticTexts[
      "The team agreed on the launch date and split the open tasks between two people."]
    XCTAssertTrue(field.waitForExistence(timeout: 15))
    XCTAssertTrue(lastMessage.waitForExistence(timeout: 15))
    let oneLineHeight = field.frame.height

    field.tap()
    field.typeText("Look what happens when I write a message that is long enough to wrap")
    XCTAssertTrue(
      waitUntil { field.frame.height > oneLineHeight + 10 }, "The field did not grow to two lines")

    let isAboveComposer = waitUntil {
      lastMessage.exists && lastMessage.isHittable && lastMessage.frame.maxY <= field.frame.minY
        && field.frame.minY - lastMessage.frame.maxY < 80
    }
    XCTAssertTrue(isAboveComposer, "The history vanished or left the composer while it grew")
  }

  @MainActor private func openHermes() -> XCUIApplication {
    let service = "http://127.0.0.1:8765"
    var reset = URLRequest(url: URL(string: "\(service)/__reset")!)
    reset.httpMethod = "POST"
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: reset) { _, _, _ in done.signal() }.resume()
    _ = done.wait(timeout: .now() + 10)

    let app = XCUIApplication()
    app.launchArguments = ["-serviceURL", service]
    app.launch()

    let hermes = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", "Hermes"))
      .firstMatch
    XCTAssertTrue(hermes.waitForExistence(timeout: 30))
    hermes.tap()
    return app
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
