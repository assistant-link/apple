import XCTest

/// A circle button must take taps on its whole 44 pt target, which reaches past the drawn disc.
final class CircleButtonTests: XCTestCase {
  @MainActor func testVoiceButtonAndCallSheetButtonsTakeTapsNearTheirEdge() {
    let app = XCUIApplication()
    app.launchArguments = ["-componentCatalog", "chat"]
    app.launch()

    let voice = app.buttons["voiceButton"]
    XCTAssertTrue(voice.waitForExistence(timeout: 30))
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

  @MainActor func testPullingTheCallSheetDownKeepsEndAndATapBringsItBack() {
    let app = XCUIApplication()
    app.launchArguments = ["-componentCatalog", "call-live"]
    app.launch()

    XCTAssertTrue(app.buttons["voiceMute"].waitForExistence(timeout: 30))
    let grabber = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
    grabber.press(forDuration: 0.1, thenDragTo: grabber.withOffset(CGVector(dx: 0, dy: 700)))
    let bar = app.descendants(matching: .any)["compactCallBar"].firstMatch
    XCTAssertTrue(bar.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["voiceMute"].exists)
    assertHitTarget(app.buttons["voiceEnd"])

    bar.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["voiceMute"].waitForExistence(timeout: 5))
  }

  // The navigation bar reports its own ~39 pt frame for the voice button, so only the circle controls are measured.
  private func assertHitTarget(_ element: XCUIElement) {
    XCTAssertGreaterThanOrEqual(element.frame.width, 44, element.identifier)
    XCTAssertGreaterThanOrEqual(element.frame.height, 44, element.identifier)
  }

  /// 12% of a circle control's 44 pt target lies outside its drawn disc.
  private func nearEdge(of element: XCUIElement) -> XCUICoordinate {
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
  }
}
