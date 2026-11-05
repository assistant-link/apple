import XCTest

/// A circle button must take taps on its whole 44 pt target, which reaches past the drawn disc.
final class CircleButtonTests: XCTestCase {
  @MainActor func testVoiceButtonAndBannerButtonsTakeTapsNearTheirEdge() {
    let app = XCUIApplication()
    app.launchArguments = ["-componentCatalog", "chat"]
    app.launch()

    let voice = app.buttons["voiceButton"]
    XCTAssertTrue(voice.waitForExistence(timeout: 30))
    assertHitTarget(voice)
    nearEdge(of: voice).tap()

    let mute = app.buttons["voiceMute"]
    XCTAssertTrue(mute.waitForExistence(timeout: 10), "a tap near the voice button's edge missed")
    XCTAssertFalse(voice.exists, "the start control stays while the call is on")
    XCTAssertEqual(mute.label, "Mute")
    assertHitTarget(mute)
    assertHitTarget(app.buttons["voiceEnd"])
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
    // swipeUp() on a 64 pt tall element drags too short and fast to pass the gesture's threshold.
    let start = banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)))
    XCTAssertTrue(app.buttons["showCallBanner"].waitForExistence(timeout: 5))
    XCTAssertFalse(end.exists)

    assertHitTarget(app.buttons["showCallBanner"])
    app.buttons["showCallBanner"].tap()
    XCTAssertTrue(end.waitForExistence(timeout: 5))
  }

  private func assertHitTarget(_ element: XCUIElement) {
    XCTAssertGreaterThanOrEqual(element.frame.width, 44, element.identifier)
    XCTAssertGreaterThanOrEqual(element.frame.height, 44, element.identifier)
  }

  /// The disc is at most 40 pt wide, so 12% of a 44 pt target lies outside it.
  private func nearEdge(of element: XCUIElement) -> XCUICoordinate {
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
  }
}
