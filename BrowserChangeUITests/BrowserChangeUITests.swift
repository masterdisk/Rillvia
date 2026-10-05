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
            app.staticTexts["routing-summary-title"].exists,
            "Live routing state should remain visible but secondary."
        )
        XCTAssertTrue(app.buttons["nav-airlock"].exists)
        XCTAssertTrue(app.buttons["nav-rules"].exists)
        XCTAssertTrue(app.buttons["nav-profiles"].exists)
        XCTAssertFalse(
            app.staticTexts["Where links could go"].exists,
            "The old dashboard-style preview heading should be removed."
        )

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "browserchange-redesign"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let safari = app.descendants(matching: .any)["Safari"].firstMatch
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

    func testSplitHandlersCanBeRepairedWithTheSelectedBrowser() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
            "--ui-testing-split-handlers",
        ]
        app.launch()

        let warning = app.staticTexts["split-handler-warning"]
        XCTAssertTrue(
            warning.waitForExistence(timeout: 4),
            "A split HTTP/HTTPS state should be explained in the main workspace."
        )

        app.descendants(matching: .any)["Safari"].firstMatch.click()
        let repair = app.buttons["Repair handlers with Safari"]
        XCTAssertTrue(repair.waitForExistence(timeout: 2))
        repair.click()

        XCTAssertTrue(
            warning.waitForNonExistence(timeout: 2),
            "Repair should leave both fake handlers on the selected browser."
        )
        XCTAssertTrue(
            app.buttons["Undo last browser change"].waitForExistence(timeout: 2)
        )
    }

    func testAirlockPreviewsAndTeachesRuleOnlyAfterExplicitOpen() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
        ]
        app.launch()

        let enable = app.buttons[
            "Turn on Smart Routing with Google Chrome"
        ]
        XCTAssertTrue(enable.waitForExistence(timeout: 4))
        enable.click()

        let airlock = app.buttons["nav-airlock"]
        XCTAssertTrue(airlock.waitForExistence(timeout: 2))
        airlock.click()

        let input = app.textViews["airlock-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        input.click()
        input.typeText(
            "https://Docs.Example.com/private?utm_source=mail"
        )
        app.buttons["airlock-preview"].click()

        XCTAssertTrue(
            app.staticTexts["docs.example.com"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["Google Chrome"].exists)

        app.buttons["airlock-open-in"].click()
        let always = app.checkBoxes["chooser-always"]
        XCTAssertTrue(always.waitForExistence(timeout: 2))
        always.click()
        app.radioButtons["Include subdomains"].click()
        app.buttons["chooser-open-Safari"].click()

        app.buttons["nav-rules"].click()
        XCTAssertTrue(
            app.staticTexts["rules-title"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["docs.example.com"].exists)
        XCTAssertTrue(app.staticTexts["Include subdomains"].exists)
    }

    func testSuccessfulDirectSwitchCanBeUndoneFromTheMainWorkspace() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
        ]
        app.launch()

        app.descendants(matching: .any)["Safari"].firstMatch.click()
        let makeDefault = app.buttons["Make Safari the default"]
        XCTAssertTrue(makeDefault.waitForExistence(timeout: 2))
        makeDefault.click()

        let undo = app.buttons["Undo last browser change"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        undo.click()

        XCTAssertTrue(
            app.buttons["Make Safari the default"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.staticTexts["Restored the previous web-link handlers."]
                .waitForExistence(timeout: 2)
        )
    }

    func testSmartRoutingModeAndFallbackTransitionsAreExplicit() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["routing-mode-title"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Direct"].exists)

        let enable = app.buttons[
            "Turn on Smart Routing with Google Chrome"
        ]
        XCTAssertTrue(enable.waitForExistence(timeout: 2))
        enable.click()

        XCTAssertTrue(
            app.staticTexts["Smart Routing"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.buttons[
                "Turn off Smart Routing and make Google Chrome the Direct default"
            ].exists
        )

        app.descendants(matching: .any)["Safari"].firstMatch.click()
        let useSafari = app.buttons[
            "Use Safari as Smart Routing fallback"
        ]
        XCTAssertTrue(useSafari.waitForExistence(timeout: 2))
        useSafari.click()

        let disable = app.buttons[
            "Turn off Smart Routing and make Safari the Direct default"
        ]
        XCTAssertTrue(disable.waitForExistence(timeout: 2))
        disable.click()

        XCTAssertTrue(
            app.staticTexts["Direct"].waitForExistence(timeout: 2)
        )
    }

    func testConfiguredSmartWithExternalHandlersDisplaysSuspendedState() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
            "--ui-testing-smart-suspended",
        ]
        app.launch()

        let modeTitle = app.staticTexts["routing-mode-title"]
        XCTAssertTrue(modeTitle.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Smart Routing suspended"].exists)
        XCTAssertTrue(app.staticTexts["routing-mode-detail"].exists)
        XCTAssertTrue(
            app.buttons[
                "Turn off Smart Routing and make Google Chrome the Direct default"
            ].exists
        )
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
