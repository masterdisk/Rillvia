import AppKit
import XCTest

final class BrowserChangeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMainWindowPrioritizesChoosingTheDefaultBrowser() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["workspace-title"].waitForExistence(timeout: 4),
            "The primary heading should state the job of the window."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["browser-sidebar"].exists,
            "Installed browsers should be presented in a native sidebar."
        )
        XCTAssertTrue(
            app.staticTexts["future-features-title"].exists,
            "Future ideas should remain visible but secondary."
        )
        XCTAssertFalse(
            app.staticTexts["Where links could go"].exists,
            "The old dashboard-style preview heading should be removed."
        )

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "browserchange-redesign"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let safari = app.staticTexts["Safari"].firstMatch
        XCTAssertTrue(safari.exists)
        safari.click()
        XCTAssertTrue(
            app.buttons["Make Safari the default"].waitForExistence(timeout: 2),
            "Selecting another browser should reveal one clear primary action."
        )

        let selectionScreenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        selectionScreenshot.name = "browserchange-selection"
        selectionScreenshot.lifetime = .keepAlways
        add(selectionScreenshot)
    }

    func testMainWindowInDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--force-dark-appearance",
            "--ui-testing",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["workspace-title"].waitForExistence(timeout: 4))

        let windowScreenshot = app.windows.firstMatch.screenshot()
        XCTAssertLessThan(
            sampledLuminance(of: windowScreenshot.image),
            0.5,
            "The window should render with a genuinely dark semantic background."
        )

        let screenshot = XCTAttachment(screenshot: windowScreenshot)
        screenshot.name = "browserchange-dark"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func sampledLuminance(of image: NSImage) -> CGFloat {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let color = bitmap.colorAt(
                x: Int(Double(bitmap.pixelsWide) * 0.9),
                y: Int(Double(bitmap.pixelsHigh) * 0.5)
              )?.usingColorSpace(.deviceRGB) else {
            XCTFail("Could not sample the dark appearance screenshot.")
            return 1
        }
        return (0.2126 * color.redComponent)
            + (0.7152 * color.greenComponent)
            + (0.0722 * color.blueComponent)
    }
}
