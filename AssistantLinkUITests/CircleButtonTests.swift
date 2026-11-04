import XCTest

/// A circle button must take taps on its whole disc, not only on its glyph.
final class CircleButtonTests: XCTestCase {
  @MainActor func testBannerAndComposerButtonsTakeTapsNearTheirEdge() {
    let app = XCUIApplication()
    app.launchArguments = ["-componentCatalog", "chat"]
    app.launch()

    let voice = app.buttons["voiceButton"]
    XCTAssertTrue(voice.waitForExistence(timeout: 30))
    nearEdge(of: voice).tap()

    let mute = app.buttons["voiceMute"]
    XCTAssertTrue(mute.waitForExistence(timeout: 10), "a tap near the voice button's edge missed")
    XCTAssertEqual(mute.label, "Mute")
    nearEdge(of: mute).tap()
    XCTAssertTrue(
      app.buttons["Unmute"].waitForExistence(timeout: 5), "a tap near the mute button's edge missed"
    )

    nearEdge(of: app.buttons["voiceEnd"]).tap()
    XCTAssertTrue(
      app.buttons["voiceButton"].waitForExistence(timeout: 10),
      "a tap near the end button's edge missed")
  }

  @MainActor func testSwipingTheBannerUpHidesItAndTheChevronBringsItBack() {
    let app = XCUIApplication()
    app.launchArguments = ["-componentCatalog", "call-live"]
    app.launch()

    let end = app.buttons["voiceEnd"]
    XCTAssertTrue(end.waitForExistence(timeout: 30))
    let banner = app.descendants(matching: .any)["callBanner"].firstMatch
    banner.swipeUp()
    XCTAssertTrue(app.buttons["showCallBanner"].waitForExistence(timeout: 5))
    XCTAssertFalse(end.exists)

    app.buttons["showCallBanner"].tap()
    XCTAssertTrue(end.waitForExistence(timeout: 5))
  }

  private func nearEdge(of element: XCUIElement) -> XCUICoordinate {
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
  }
}
