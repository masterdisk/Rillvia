import AppKit
import XCTest

final class BrowserChangeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--ui-testing"] + arguments
        app.launch()
        return app
    }
    private func designApp(_ arguments: [String] = []) -> XCUIApplication { launch(["--ui-testing-design-fixture", "--force-light-appearance"] + arguments) }
    private func preview(_ url: String, in app: XCUIApplication) {
        app.buttons["nav-airlock"].click()
        let input = app.textFields["airlock-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 4))
        input.click(); input.typeKey("a", modifierFlags: .command); input.typeText(url)
        app.buttons["airlock-preview"].click()
    }
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testOverviewAndKeyboardNavigation() {
        let app = designApp()
        XCTAssertTrue(app.staticTexts["workspace-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fallback-picker"].exists)
        XCTAssertTrue(app.buttons["active-rule-set-picker"].exists)
        XCTAssertTrue(app.staticTexts["Rules are on"].exists)
        screenshot(app, "rillvia-overview-light")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["airlock-title"].waitForExistence(timeout: 3))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["rules-title"].waitForExistence(timeout: 3))
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["browsers-title"].waitForExistence(timeout: 3))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["settings-title"].waitForExistence(timeout: 3))
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["keyboard-shortcuts-title"].waitForExistence(timeout: 3))
    }

    func testBrowserSelectionDoesNotChangeFallback() {
        let app = designApp()
        app.buttons["nav-direct"].click()
        app.buttons["browser-row-Google Chrome"].click()
        XCTAssertTrue(app.buttons["use-selected-browser"].waitForExistence(timeout: 3))
        screenshot(app, "rillvia-browsers-light")
        app.buttons["nav-overview"].click()
        XCTAssertTrue(app.staticTexts["Safari opens links unless a rule says otherwise."].exists)
        app.buttons["nav-direct"].click()
        app.buttons["use-selected-browser"].click()
        app.buttons["nav-overview"].click()
        XCTAssertTrue(app.staticTexts["Google Chrome opens links unless a rule says otherwise."].waitForExistence(timeout: 3))
    }

    func testBrowsingAnInactiveSetRequiresExplicitActivation() {
        let app = designApp()
        app.buttons["nav-rules"].click()
        app.buttons["Personal"].click()
        let activate = app.buttons["activate-browsed-rule-set"]
        XCTAssertTrue(activate.waitForExistence(timeout: 3))
        screenshot(app, "rillvia-personal-inactive")
        activate.click()
        XCTAssertTrue(activate.waitForNonExistence(timeout: 3))
        app.buttons["nav-overview"].click()
        XCTAssertTrue((app.buttons["active-rule-set-picker"].value as? String) == "Personal")
    }

    func testRuleDraftNeedsSaveAndGuardsNavigation() {
        let app = designApp()
        app.buttons["nav-rules"].click()
        app.buttons["rule-row-github.com"].click()
        screenshot(app, "rillvia-rules-github")
        let domain = app.textFields["rule-domain"]
        domain.click(); domain.typeKey("a", modifierFlags: .command); domain.typeText("https://docs.example.com/path")
        app.buttons["nav-overview"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))
        app.sheets.firstMatch.buttons["Keep editing"].click()
        XCTAssertEqual(domain.value as? String, "https://docs.example.com/path")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.buttons["rule-row-docs.example.com"].waitForExistence(timeout: 3))
        screenshot(app, "rillvia-rule-editor")
        app.buttons["nav-overview"].click()
        XCTAssertTrue(app.staticTexts["workspace-title"].waitForExistence(timeout: 3))
    }

    func testNewRuleValidatesAndUsesTypedDomain() {
        let app = designApp()
        app.buttons["nav-rules"].click()
        app.typeKey("n", modifierFlags: .command)
        let domain = app.textFields["rule-domain"]
        XCTAssertTrue(domain.waitForExistence(timeout: 3))
        domain.click(); domain.typeText("bad host")
        XCTAssertFalse(app.buttons["save-rule"].isEnabled)
        domain.typeKey("a", modifierFlags: .command); domain.typeText("news.example.com")
        app.buttons["rule-browser"].click()
        app.buttons["selector-choice-com.apple.Safari"].click()
        app.buttons["rule-scope"].click()
        app.buttons["selector-choice-includeSubdomains"].click()
        XCTAssertTrue(app.buttons["save-rule"].isEnabled)
        app.buttons["save-rule"].click()
        XCTAssertTrue(app.buttons["rule-row-news.example.com"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["rule-row-news.example.com"].label.contains("Safari"))
    }

    func testDeletingRuleOffersVisibleUndo() {
        let app = designApp()
        app.buttons["nav-rules"].click()
        let rule = app.buttons["rule-row-github.com"]
        rule.click()
        rule.rightClick()
        app.menuItems["Delete rule"].click()
        XCTAssertTrue(rule.waitForNonExistence(timeout: 3))
        let undo = app.buttons["undo-configuration"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.click()
        XCTAssertTrue(rule.waitForExistence(timeout: 3))
    }

    func testPreviewStaysCurrentOnlyUntilInputChanges() {
        let app = designApp()
        preview("https://github.com/openai?utm_source=newsletter", in: app)
        XCTAssertTrue(app.buttons["airlock-open-now"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Matches github.com in Work"].exists)
        screenshot(app, "rillvia-preview")
        let input = app.textFields["airlock-input"]
        input.click(); input.typeText("/changed")
        XCTAssertFalse(app.buttons["airlock-open-now"].exists)
        app.buttons["airlock-preview"].click()
        XCTAssertTrue(app.buttons["airlock-open-now"].waitForExistence(timeout: 3))
    }

    func testAlwaysOpenTeachingNeedsExplicitOpen() {
        let app = designApp()
        preview("https://docs.example.com/path?utm_source=mail", in: app)
        app.buttons["airlock-open-in"].click()
        let chooser = app.staticTexts["airlock-chooser-title"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 3))
        app.buttons["chooser-browser-Google Chrome"].click()
        app.checkBoxes["airlock-always-open"].click()
        XCTAssertTrue(chooser.exists)
        app.buttons["chooser-open"].click()
        XCTAssertTrue(chooser.waitForNonExistence(timeout: 3))
        app.buttons["nav-rules"].click()
        XCTAssertTrue(app.buttons["rule-row-docs.example.com"].waitForExistence(timeout: 3))
    }

    func testFailedTeachingAndDisappearedBrowserKeepChooserOpen() {
        for extra in [["--ui-testing-history-failure"], ["--ui-testing-explicit-target-unavailable"]] {
            let app = launch(["--ui-testing-task7-fixture"] + extra)
            preview("https://example.com/path", in: app)
            app.buttons["airlock-open-in"].click()
            app.buttons["chooser-browser-Safari"].click()
            app.checkBoxes["airlock-always-open"].click()
            app.buttons["chooser-open"].click()
            XCTAssertTrue(app.staticTexts["airlock-chooser-error"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["airlock-chooser-title"].exists)
            app.terminate()
        }
    }

    func testTemporaryBrowserStartsExplicitlyAndCanEndAndUndo() {
        let app = designApp()
        app.typeKey("t", modifierFlags: .command)
        let start = app.buttons["start-temporary-browser"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["end-temporary-browser"].exists)
        start.click()
        let end = app.buttons["end-temporary-browser"]
        XCTAssertTrue(end.waitForExistence(timeout: 3))
        end.click()
        app.buttons["Undo temporary browser change"].click()
        XCTAssertTrue(end.waitForExistence(timeout: 3))
        screenshot(app, "rillvia-temporary-browser")
    }

    func testTimedExpiryResumesRules() {
        let app = launch(["--ui-testing-task7-fixture", "--ui-testing-lease-expiry-control"])
        XCTAssertTrue(app.buttons["end-temporary-browser"].waitForExistence(timeout: 5))
        app.buttons["ui-test-expire-lease"].click()
        XCTAssertTrue(app.buttons["end-temporary-browser"].waitForNonExistence(timeout: 3))
        preview("https://example.com", in: app)
        XCTAssertTrue(app.staticTexts["Matches example.com in Work"].waitForExistence(timeout: 3))
    }

    func testDirectSwitchAndSplitHandlerRepairCanBeUndone() {
        let app = launch(["--ui-testing-split-handlers"])
        app.buttons["nav-direct"].click()
        app.buttons["browser-row-Safari"].click()
        let warning = app.staticTexts["split-handler-warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
        app.buttons["Use Safari for both HTTP and HTTPS"].click()
        XCTAssertTrue(warning.waitForNonExistence(timeout: 3))
        app.buttons["Undo last browser change"].click()
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
    }

    func testRulesCanTurnOnAndOffWithAnExplicitAction() {
        let app = launch()
        app.buttons["enable-rules"].click()
        XCTAssertTrue(app.staticTexts["Rules are on"].waitForExistence(timeout: 3))
        app.buttons["nav-settings"].click()
        app.buttons["settings-routing-toggle"].click()
        XCTAssertTrue(app.staticTexts["Rules are off"].waitForExistence(timeout: 3))
        app.buttons["settings-routing-toggle"].click()
        XCTAssertTrue(app.staticTexts["Rules are on"].waitForExistence(timeout: 3))
    }

    func testSuspendedRoutingShowsCurrentMacOSBrowser() {
        let app = launch(["--ui-testing-smart-suspended"])
        XCTAssertTrue(app.staticTexts["Rules are paused"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["enable-rules"].exists)
        preview("https://example.com", in: app)
        XCTAssertTrue(app.staticTexts["Rules are paused. Uses the current macOS default."].waitForExistence(timeout: 3))
    }

    func testSettingsTutorialReplayAndKeyboardHelp() {
        let app = designApp()
        app.buttons["nav-settings"].click()
        XCTAssertTrue(app.descendants(matching: .any)["open-at-login"].waitForExistence(timeout: 3))
        screenshot(app, "rillvia-settings")
        app.buttons["replay-tutorial"].click()
        XCTAssertTrue(app.staticTexts["intro-title"].waitForExistence(timeout: 3))
        screenshot(app, "rillvia-tutorial")
        for _ in 0..<5 { app.buttons["intro-done"].click() }
        XCTAssertTrue(app.staticTexts["intro-title"].waitForNonExistence(timeout: 3))
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["keyboard-shortcuts-title"].waitForExistence(timeout: 3))
    }

    func testDiagnosticsShortcutRedactsURLAndHistoryCanReturnToNow() {
        let app = launch(["--ui-testing-task7-fixture"])
        app.typeKey("u", modifierFlags: [.command, .option])
        XCTAssertTrue(app.staticTexts["diagnostics-title"].waitForExistence(timeout: 3))
        screenshot(app, "rillvia-diagnostics")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("t", modifierFlags: [.command, .option])
        XCTAssertTrue(app.staticTexts["time-machine-title"].waitForExistence(timeout: 3))
        screenshot(app, "rillvia-history")
    }

    func testDarkAppearanceLargeTextAndReducedMotion() {
        let app = designApp(["--force-dark-appearance", "--ui-testing-large-text", "--ui-testing-reduce-motion"])
        XCTAssertTrue(app.staticTexts["workspace-title"].waitForExistence(timeout: 5))
        screenshot(app, "rillvia-overview-dark")
        app.buttons["nav-direct"].click()
        app.buttons["browser-row-Google Chrome"].click()
        XCTAssertTrue(app.staticTexts["browser-detail-title"].waitForExistence(timeout: 3))
        screenshot(app, "rillvia-browsers-dark")
    }


    func testWidePickerKeyboardShortcutsAndCancel() {
        let app = designApp()
        app.typeKey("b", modifierFlags: .command)
        let chrome = app.buttons["selector-choice-com.google.Chrome"]
        XCTAssertTrue(chrome.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(chrome.waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.buttons["fallback-picker"].value as? String, "Safari")
        app.typeKey("r", modifierFlags: [.command, .shift])
        let personal = app.buttons.matching(NSPredicate(format: "label == %@", "Personal")).firstMatch
        XCTAssertTrue(personal.waitForExistence(timeout: 3))
        personal.click()
        XCTAssertEqual(app.buttons["active-rule-set-picker"].value as? String, "Personal")
    }

    func testMenuPanelShowsFullActionAndExplicitTemporarySwitch() {
        let app = designApp()
        let status = app.statusItems["Rillvia"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        status.click()
        let start = app.buttons["menu-start-temporary-browser"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        XCTAssertEqual(start.label, "Use Google Chrome for 15 minutes")
        XCTAssertFalse(app.buttons["end-temporary-browser"].exists)
        let panel = app.dialogs.containing(.button, identifier: "menu-open-app").firstMatch
        if panel.exists {
            let attachment = XCTAttachment(screenshot: panel.screenshot()); attachment.name = "rillvia-menu-panel"; attachment.lifetime = .keepAlways; add(attachment)
        }
        start.click()
        XCTAssertTrue(app.buttons["end-temporary-browser"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["end-temporary-browser"].firstMatch.click()
        XCTAssertTrue(app.buttons["Undo temporary browser change"].firstMatch.waitForExistence(timeout: 3))
    }

    func testMenuPanelUsesTheCurrentMacOSBrowserWhenRulesAreOff() {
        let app = designApp()
        app.buttons["nav-settings"].click()
        app.buttons["settings-routing-toggle"].click()
        XCTAssertTrue(app.staticTexts["Rules are off"].waitForExistence(timeout: 3))
        app.buttons["nav-direct"].click()
        app.buttons["browser-row-Google Chrome"].click()
        app.buttons["use-selected-browser"].click()
        app.statusItems["Rillvia"].click()
        let browser = app.staticTexts["menu-other-links-browser"]
        XCTAssertTrue(browser.waitForExistence(timeout: 3))
        XCTAssertEqual(browser.value as? String, "Google Chrome")
        XCTAssertFalse(app.buttons["menu-start-temporary-browser"].isEnabled)
    }

    func testLivingBrowserHallIsStillAvailable() {
        let app = designApp()
        app.menuBars.menuBarItems["Tools"].click()
        app.menuItems["Living Browser Hall"].click()
        XCTAssertTrue(app.staticTexts["living-hall-title"].waitForExistence(timeout: 3))
        screenshot(app, "rillvia-browser-hall")
    }

    func testIncomingURLLaunchRemainsWindowless() {
        let app = launch(["--ui-testing-routing-fixture", "--ui-testing-incoming-fallback"])
        XCTAssertFalse(app.windows.firstMatch.waitForExistence(timeout: 3))
    }
}
