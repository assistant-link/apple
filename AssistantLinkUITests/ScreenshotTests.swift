import XCTest

final class ScreenshotTests: XCTestCase {
  @MainActor func testCaptureKeyScreens() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-serviceURL", "http://127.0.0.1:8765"]
    app.launch()

    XCTAssertTrue(row("Hermes", in: app).waitForExistence(timeout: 30))
    capture(app, "1-list")

    row("Hermes", in: app).tap()
    XCTAssertTrue(backButton(in: app).waitForExistence(timeout: 10))
    capture(app, "2-hermes")

    backButton(in: app).tap()
    XCTAssertTrue(row("Grok Bot", in: app).waitForExistence(timeout: 10))
    row("Grok Bot", in: app).tap()
    XCTAssertTrue(backButton(in: app).waitForExistence(timeout: 10))
    capture(app, "3-grok-bot-setup")
  }

  @MainActor private func row(_ name: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", name))
      .firstMatch
  }

  @MainActor private func backButton(in app: XCUIApplication) -> XCUIElement {
    app.navigationBars.buttons.element(boundBy: 0)
  }

  @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
