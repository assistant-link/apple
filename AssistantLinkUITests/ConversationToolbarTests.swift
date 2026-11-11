import XCTest

/// The conversation toolbar holds the title, which opens Details, and the call button.
final class ConversationToolbarTests: XCTestCase {
  @MainActor func testTheToolbarHasACallButtonAndNoMoreMenu() {
    let app = XCUIApplication()
    app.launchArguments = ["-componentCatalog", "chat"]
    app.launch()

    let call = app.buttons["voiceButton"]
    XCTAssertTrue(call.waitForExistence(timeout: 30))
    XCTAssertEqual(call.label, "Call")
    XCTAssertFalse(app.buttons["moreButton"].exists)
    XCTAssertFalse(app.navigationBars.buttons["More"].exists)
  }
}
