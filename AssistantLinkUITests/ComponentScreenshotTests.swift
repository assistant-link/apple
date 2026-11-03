import XCTest

/// Captures each section of the component catalog; the names start with a number so the
/// screenshots job exports them.
final class ComponentScreenshotTests: XCTestCase {
  @MainActor func testCaptureComponents() {
    for (index, section) in ["messages", "composer", "call"].enumerated() {
      let app = XCUIApplication()
      app.launchArguments = ["-componentCatalog", section]
      app.launch()
      XCTAssertTrue(
        app.descendants(matching: .any)["componentCatalog"].waitForExistence(timeout: 30),
        "the \(section) catalog did not appear")
      // Lets the glass settle.
      Thread.sleep(forTimeInterval: 1)
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = "\(20 + index)-components-\(section)"
      attachment.lifetime = .keepAlways
      add(attachment)
      app.terminate()
    }
  }
}
