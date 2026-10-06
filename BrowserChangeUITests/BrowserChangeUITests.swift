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
            app.staticTexts["routing-mode-title"].exists,
            "The browser page should show where links open."
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

        let safari = app.buttons["browser-row-Safari"]
        XCTAssertTrue(safari.exists)
        safari.click()
        XCTAssertTrue(
            app.buttons["Make Safari the usual browser"].waitForExistence(timeout: 2),
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

        app.buttons["browser-row-Safari"].click()
        let repair = app.buttons["Use Safari for both HTTP and HTTPS"]
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
            "Send links through Linkpick. Otherwise use Google Chrome."
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
        app.radioButtons["This site and subdomains"].click()
        app.buttons["chooser-open-Safari"].click()

        app.buttons["nav-rules"].click()
        XCTAssertTrue(
            app.staticTexts["rules-title"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["docs.example.com"].exists)
        XCTAssertTrue(app.staticTexts["This site and subdomains"].exists)
    }

    func testSuccessfulDirectSwitchCanBeUndoneFromTheMainWorkspace() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
        ]
        app.launch()

        app.buttons["browser-row-Safari"].click()
        let makeDefault = app.buttons["Make Safari the usual browser"]
        XCTAssertTrue(makeDefault.waitForExistence(timeout: 2))
        makeDefault.click()

        let undo = app.buttons["Undo last browser change"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        undo.click()

        XCTAssertTrue(
            app.buttons["Make Safari the usual browser"].waitForExistence(timeout: 2)
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
        XCTAssertTrue(app.staticTexts["Usual browser"].exists)

        let enable = app.buttons[
            "Send links through Linkpick. Otherwise use Google Chrome."
        ]
        XCTAssertTrue(enable.waitForExistence(timeout: 2))
        enable.click()

        XCTAssertTrue(
            app.staticTexts["Sending links"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.buttons[
                "Stop. Make Google Chrome the usual browser."
            ].exists
        )

        app.buttons["browser-row-Safari"].click()
        let useSafari = app.buttons[
            "Use Safari when no rule matches"
        ]
        XCTAssertTrue(useSafari.waitForExistence(timeout: 2))
        useSafari.click()

        let disable = app.buttons[
            "Stop. Make Safari the usual browser."
        ]
        XCTAssertTrue(disable.waitForExistence(timeout: 2))
        disable.click()

        XCTAssertTrue(
            app.staticTexts["Usual browser"].waitForExistence(timeout: 2)
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
        XCTAssertTrue(app.staticTexts["Link sending paused"].exists)
        XCTAssertTrue(app.staticTexts["routing-mode-detail"].exists)
        XCTAssertTrue(
            app.buttons[
                "Stop. Make Google Chrome the usual browser."
            ].exists
        )
    }

    func testSmartRoutingExplainsAndControlsFocusAutomationPermission() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
        ]
        app.launch()

        let enable = app.buttons[
            "Send links through Linkpick. Otherwise use Google Chrome."
        ]
        XCTAssertTrue(enable.waitForExistence(timeout: 4))
        enable.click()

        let permission = app.checkBoxes[
            "allow-automation-leases"
        ]
        XCTAssertTrue(permission.waitForExistence(timeout: 2))
        XCTAssertEqual(permission.value as? Int, 0)

        permission.click()

        XCTAssertEqual(permission.value as? Int, 1)
        XCTAssertTrue(
            app.staticTexts[
                "Shortcuts can now switch browsers."
            ].waitForExistence(timeout: 2)
        )
    }

    func testSmartBrowserLeaseCanStartEndAndUndoFromMainWindow() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
        ]
        app.launch()

        let enable = app.buttons[
            "Send links through Linkpick. Otherwise use Google Chrome."
        ]
        XCTAssertTrue(enable.waitForExistence(timeout: 4))
        enable.click()

        app.buttons["browser-row-Safari"].click()
        let borrow = app.descendants(matching: .any)[
            "borrow-browser-Safari"
        ]
        XCTAssertTrue(
            borrow.waitForExistence(timeout: 2),
            "Sending links should offer a temporary browser for the selected one."
        )
        borrow.click()
        let fifteenMinutes = app.menuItems["15 minutes"]
        XCTAssertTrue(fifteenMinutes.waitForExistence(timeout: 2))
        fifteenMinutes.click()

        let activeTitle = app.descendants(matching: .any)[
            "active-lease-title"
        ]
        XCTAssertTrue(
            activeTitle.waitForExistence(timeout: 2)
        )
        let remaining = app.descendants(matching: .any)[
            "active-lease-remaining"
        ]
        XCTAssertTrue(remaining.exists)
        XCTAssertEqual(remaining.value as? String, "15:00 remaining")
        let end = app.buttons["end-browser-lease"]
        XCTAssertTrue(end.exists)
        XCTAssertTrue(app.buttons["undo-browser-lease"].exists)

        end.click()

        XCTAssertTrue(
            activeTitle.waitForNonExistence(timeout: 2)
        )
        let undo = app.buttons["undo-browser-lease"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        undo.click()
        XCTAssertTrue(
            activeTitle.waitForExistence(timeout: 2)
        )
    }

    func testConfigurationMutationWithdrawsStaleLeaseUndo() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
        ]
        app.launch()

        let enable = app.buttons[
            "Send links through Linkpick. Otherwise use Google Chrome."
        ]
        XCTAssertTrue(enable.waitForExistence(timeout: 4))
        enable.click()

        app.buttons["browser-row-Safari"].click()
        let borrow = app.descendants(matching: .any)[
            "borrow-browser-Safari"
        ]
        XCTAssertTrue(borrow.waitForExistence(timeout: 2))
        borrow.click()
        app.menuItems["15 minutes"].click()

        let undo = app.buttons["undo-browser-lease"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        let permission = app.checkBoxes[
            "allow-automation-leases"
        ]
        XCTAssertTrue(permission.exists)
        permission.click()

        XCTAssertTrue(
            undo.waitForNonExistence(timeout: 2),
            "A later configuration mutation must withdraw stale lease Undo."
        )
    }

    func testFakeTimedLeaseExpiryUpdatesUIAndRoutingWithoutWaiting() {
        let app = launchTask7App(
            extraArguments: [
                "--ui-testing-lease-expiry-control",
            ]
        )
        let activeTitle = app.descendants(matching: .any)[
            "active-lease-title"
        ]
        XCTAssertTrue(activeTitle.waitForExistence(timeout: 4))

        let expire = app.buttons["ui-test-expire-lease"]
        XCTAssertTrue(expire.exists)
        expire.click()

        XCTAssertTrue(activeTitle.waitForNonExistence(timeout: 2))
        XCTAssertFalse(app.buttons["undo-browser-lease"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "The temporary browser ended. Rules and Google Chrome are in use again."
            ].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.buttons[
                "Stop. Make Google Chrome the usual browser."
            ].exists
        )

        app.buttons["nav-airlock"].click()
        let input = app.textViews["airlock-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        input.click()
        input.typeText("https://unmatched.invalid/after-expiry")
        app.buttons["airlock-preview"].click()
        let prediction = app.staticTexts[
            "airlock-predicted-browser"
        ]
        XCTAssertTrue(prediction.waitForExistence(timeout: 2))
        XCTAssertEqual(accessibleText(of: prediction), "Google Chrome")
        app.buttons["Open now"].click()
        app.buttons["nav-direct"].click()
        XCTAssertTrue(
            app.staticTexts[
                "Opened the link in Google Chrome."
            ].waitForExistence(timeout: 2)
        )
    }

    func testMenuPanelExposesBorrowCountdownEndAndUndo() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
        ]
        app.launch()

        let enable = app.buttons[
            "Send links through Linkpick. Otherwise use Google Chrome."
        ]
        XCTAssertTrue(enable.waitForExistence(timeout: 4))
        enable.click()

        let statusItem = app.statusItems[
            "Linkpick, Google Chrome"
        ]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 2))
        statusItem.click()

        let borrow = app.buttons["menu-borrow-browser"]
        XCTAssertTrue(
            borrow.waitForExistence(timeout: 2),
            "The menu panel should offer a temporary browser only while Linkpick is sending links."
        )
        borrow.click()
        let safari = app.buttons["menu-borrow-choice-Safari"]
        XCTAssertTrue(safari.waitForExistence(timeout: 2))
        safari.click()
        let confirm = app.buttons["menu-borrow-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        XCTAssertEqual(confirm.label, "Use Safari for 15 minutes")
        confirm.click()
        XCTAssertTrue(app.buttons["menu-quit"].exists)

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "menu-active-lease-title"
            ].waitForExistence(timeout: 2)
        )
        let remaining = app.descendants(matching: .any)[
            "menu-active-lease-remaining"
        ]
        XCTAssertTrue(remaining.exists)
        XCTAssertEqual(remaining.value as? String, "15:00 remaining")
        let end = app.buttons["menu-end-browser-lease"]
        XCTAssertTrue(end.exists)
        XCTAssertTrue(app.buttons["menu-undo-browser-lease"].exists)

        end.click()

        let undo = app.buttons["menu-undo-browser-lease"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        undo.click()
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "menu-active-lease-title"
            ].waitForExistence(timeout: 2)
        )
    }

    func testViewSourceShortcutOpensRedactedDiagnostics() {
        let app = launchTask7App()

        app.typeKey(
            "u",
            modifierFlags: [.command, .option]
        )

        XCTAssertTrue(
            app.staticTexts["diagnostics-title"]
                .waitForExistence(timeout: 2)
        )
        let snapshot = app.staticTexts["diagnostics-snapshot"]
        XCTAssertTrue(snapshot.exists)
        XCTAssertTrue(
            accessibleText(of: snapshot).contains(
                "Configuration schema"
            )
        )
        XCTAssertFalse(
            accessibleText(of: snapshot).contains("/private")
        )
        XCTAssertTrue(app.buttons["copy-diagnostics"].isHittable)
        attachScreenshot(
            named: "task7-diagnostics",
            app: app
        )
    }

    func testPreviewTimeMachineEvaluatesAndReturnsToNow() {
        let app = launchTask7App()

        app.typeKey(
            "t",
            modifierFlags: [.command, .option]
        )

        XCTAssertTrue(
            app.staticTexts["time-machine-title"]
                .waitForExistence(timeout: 2)
        )
        let input = app.textFields["time-machine-url"]
        XCTAssertTrue(input.isHittable)
        input.click()
        input.typeText(
            "https://example.com/private?secret=value"
        )
        app.buttons["time-machine-evaluate"].click()

        XCTAssertTrue(
            app.staticTexts["historical-result-target"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertEqual(
            accessibleText(
                of: app.staticTexts[
                    "historical-result-target"
                ]
            ),
            "Safari"
        )
        attachScreenshot(
            named: "task7-time-machine",
            app: app
        )

        app.buttons["return-to-now"].click()
        XCTAssertTrue(
            app.staticTexts["time-machine-title"]
                .waitForNonExistence(timeout: 2)
        )
    }

    func testFiveTapLivingHallShowsLiveFactsAndNetscapeFootnote() {
        let app = launchTask7App()
        let header = app.buttons["browsers-header"]
        XCTAssertTrue(header.waitForExistence(timeout: 2))

        for _ in 0..<5 {
            header.click()
        }

        XCTAssertTrue(
            app.staticTexts["living-hall-title"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.staticTexts["hall-browser-com.apple.Safari"].exists
        )
        XCTAssertTrue(
            app.staticTexts["hall-browser-com.google.Chrome"].exists
        )
        XCTAssertTrue(
            app.staticTexts["Browser for sites with no rule"].exists
        )
        app.buttons["hall-era-netscape"].click()
        XCTAssertTrue(
            app.staticTexts["netscape-footnote"]
                .waitForExistence(timeout: 1)
        )
        attachScreenshot(
            named: "task7-living-hall",
            app: app
        )
    }

    func testTask7LightAirlockRulesAndLeaseVisuals() {
        let app = launchTask7App()

        XCTAssertTrue(
            app.staticTexts["workspace-title"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["active-lease-title"]
                .exists
        )
        XCTAssertTrue(app.buttons["end-browser-lease"].isHittable)
        XCTAssertTrue(
            app.checkBoxes["allow-automation-leases"].isHittable
        )
        XCTAssertTrue(
            app.buttons["browser-row-Safari"].isHittable
        )
        XCTAssertGreaterThan(
            sampledLuminance(
                of: app.windows.firstMatch.screenshot().image
            ),
            0.5
        )
        attachScreenshot(named: "task7-light", app: app)
        attachScreenshot(named: "task7-lease", app: app)

        app.buttons["nav-airlock"].click()
        let input = app.textViews["airlock-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        input.click()
        input.typeText("https://example.com/review")
        app.buttons["airlock-preview"].click()
        XCTAssertTrue(app.buttons["airlock-open-in"].isHittable)
        attachScreenshot(named: "task7-airlock", app: app)

        app.buttons["nav-rules"].click()
        XCTAssertTrue(
            app.staticTexts["rules-title"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["Create rule"].isHittable)
        attachScreenshot(named: "task7-rules", app: app)

        app.buttons["nav-profiles"].click()
        XCTAssertTrue(
            app.staticTexts["profiles-title"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["Create rule set"].isHittable)
    }

    func testTask7DarkLargeTextReducedMotionSmoke() {
        let app = launchTask7App(
            extraArguments: [
                "--force-dark-appearance",
                "--ui-testing-large-text",
                "--ui-testing-reduce-motion",
            ]
        )

        XCTAssertTrue(
            app.staticTexts["workspace-title"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["nav-airlock"].isHittable)
        XCTAssertTrue(app.buttons["nav-rules"].isHittable)
        XCTAssertTrue(app.buttons["nav-profiles"].isHittable)
        let screenshot = app.windows.firstMatch.screenshot()
        XCTAssertLessThan(
            sampledLuminance(of: screenshot.image),
            0.5
        )
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "task7-dark-large-text-reduced-motion"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFailedAlwaysOpenTeachingKeepsChooserVisible() {
        let app = launchTask7App(
            extraArguments: [
                "--ui-testing-history-failure",
            ]
        )

        app.buttons["nav-airlock"].click()
        let input = app.textViews["airlock-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        input.click()
        input.typeText("https://example.com/private")
        app.buttons["airlock-preview"].click()
        app.buttons["airlock-open-in"].click()
        app.checkBoxes["chooser-always"].click()
        app.buttons["chooser-open-Safari"].click()

        XCTAssertTrue(
            app.staticTexts["browser-chooser-title"]
                .waitForExistence(timeout: 2)
        )
        let error = app.staticTexts["chooser-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 2))
        XCTAssertTrue(
            accessibleText(of: error).contains(
                "the “Always open” rule was not saved"
            )
        )
    }

    func testDisappearedExplicitTargetKeepsChooserVisible() {
        let app = launchTask7App(
            extraArguments: [
                "--ui-testing-explicit-target-unavailable",
            ]
        )

        app.buttons["nav-airlock"].click()
        let input = app.textViews["airlock-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 2))
        input.click()
        input.typeText("https://example.com/target-gone")
        app.buttons["airlock-preview"].click()
        app.buttons["airlock-open-in"].click()
        app.buttons["chooser-open-Safari"].click()

        XCTAssertTrue(
            app.staticTexts["browser-chooser-title"]
                .waitForExistence(timeout: 2)
        )
        let error = app.staticTexts["chooser-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 2))
        XCTAssertTrue(
            accessibleText(of: error).contains(
                "no longer available"
            )
        )
        XCTAssertTrue(
            accessibleText(of: error).contains(
                "choose another browser"
            )
        )
    }

    func testIncomingURLLaunchStaysWindowlessWhileRoutingToFallback() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
            "--ui-testing-routing-fixture",
            "--ui-testing-incoming-fallback",
            "--force-light-appearance",
        ]
        app.launch()

        XCTAssertFalse(
            app.windows.firstMatch.waitForExistence(timeout: 3),
            "A URL-handler launch must route in the background without presenting BrowserChange."
        )
    }

    func testRulesWorkspaceCreatesARuleFromATypedDomain() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
            "--force-light-appearance",
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["workspace-title"].waitForExistence(timeout: 4)
        )
        app.buttons["nav-rules"].click()
        XCTAssertTrue(
            app.staticTexts["rules-title"].waitForExistence(timeout: 2)
        )

        let domainField = app.textFields["rule-domain-field"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 2))
        domainField.click()
        domainField.typeText("news.example.com")

        let createRule = app.buttons["Create rule"]
        XCTAssertTrue(createRule.isEnabled)
        createRule.click()

        XCTAssertTrue(
            app.staticTexts["news.example.com"].waitForExistence(timeout: 2),
            "Creating a rule must persist the typed domain in the list."
        )
    }

    private func launchTask7App(
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
            "--ui-testing-task7-fixture",
            "--force-light-appearance",
        ] + extraArguments
        app.launch()
        return app
    }

    private func attachScreenshot(
        named name: String,
        app: XCUIApplication
    ) {
        let attachment = XCTAttachment(
            screenshot: app.windows.firstMatch.screenshot()
        )
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func accessibleText(
        of element: XCUIElement
    ) -> String {
        if !element.label.isEmpty {
            return element.label
        }
        return element.value as? String ?? ""
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
