import XCTest

/// Captures each state of the dictation design; the names start with a number so the
/// screenshots job exports them.
final class DictationScreenshotTests: XCTestCase {
  @MainActor func testCaptureDictation() {
    let pages = [
      "dictation-idle", "dictation-preparing", "dictation-recording", "dictation-recording-long",
      "dictation-editing",
    ]
    for (index, page) in pages.enumerated() {
      let app = XCUIApplication()
      app.launchArguments = ["-componentCatalog", page]
      app.launch()
      XCTAssertTrue(
        app.descendants(matching: .any)["componentCatalog"].waitForExistence(timeout: 30),
        "the \(page) page did not appear")
      // Lets the glass settle.
      Thread.sleep(forTimeInterval: 1)
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = "\(50 + index)-\(page)"
      attachment.lifetime = .keepAlways
      add(attachment)
      app.terminate()
    }
  }
}
