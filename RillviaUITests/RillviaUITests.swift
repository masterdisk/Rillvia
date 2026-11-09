import AppKit
import XCTest

final class RillviaUITests: XCTestCase {
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
        XCTAssertTrue(app.descendants(matching: .any)["workspace-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["fallback-picker"].exists)
        XCTAssertTrue(app.buttons["active-rule-set-picker"].exists)
        XCTAssertTrue(app.staticTexts["Rules are on"].exists)
        screenshot(app, "rillvia-overview-light")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["airlock-title"].waitForExistence(timeout: 3))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["rules-title"].waitForExistence(timeout: 3))
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["browsers-title"].waitForExistence(timeout: 3))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["settings-title"].waitForExistence(timeout: 3))
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["keyboard-shortcuts-title"].waitForExistence(timeout: 3))
    }

    func testSelectorGeometryAndKeyboardChoiceAtMinimumWindowSize() {
        let app = designApp(["--ui-testing-minimum-size"])
        let browser = app.buttons["fallback-picker"]
        let ruleSet = app.buttons["active-rule-set-picker"]
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        XCTAssertEqual(browser.frame.height, ruleSet.frame.height, accuracy: 1)
        XCTAssertEqual(browser.frame.width, ruleSet.frame.width, accuracy: 1)
        XCTAssertGreaterThanOrEqual(browser.frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["temporary-browser"].frame.height, 44)
        XCTAssertLessThanOrEqual(ruleSet.frame.maxX, app.windows.firstMatch.frame.maxX - 20)
        screenshot(app, "rillvia-minimum-window-controls")
        app.typeKey("r", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["selector-choice-shared"].waitForExistence(timeout: 3))
        screenshot(app, "rillvia-picker-keyboard-focus")
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(ruleSet.value as? String, "Shared rules only")
        app.typeKey("r", modifierFlags: [.command, .shift])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.buttons["selector-choice-shared"].exists)
        XCTAssertEqual(ruleSet.value as? String, "Shared rules only")
    }

    func testSelectorsStayAlignedWithLargeTextAndOpaqueControls() {
        let app = designApp(["--ui-testing-large-text", "--ui-testing-reduce-transparency", "--ui-testing-increased-contrast"])
        let browser = app.buttons["fallback-picker"]
        let ruleSet = app.buttons["active-rule-set-picker"]
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        XCTAssertEqual(browser.frame.height, ruleSet.frame.height, accuracy: 1)
        XCTAssertGreaterThanOrEqual(browser.frame.height, 64)
        XCTAssertTrue(browser.isHittable)
        XCTAssertTrue(ruleSet.isHittable)
        screenshot(app, "rillvia-accessible-controls")
    }

    func testLargeTextTutorialKeepsItsNavigationVisible() {
        let app = designApp(["--ui-testing-large-text"])
        app.buttons["nav-settings"].click()
        app.buttons["replay-tutorial"].click()
        let next = app.buttons["intro-done"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        for _ in 0..<5 {
            XCTAssertTrue(next.isHittable)
            XCTAssertGreaterThanOrEqual(next.frame.height, 24)
            screenshot(app, "rillvia-tour-200-percent")
            next.click()
        }
        XCTAssertFalse(app.descendants(matching: .any)["intro-title"].exists)
    }

    func testLargeTextAcrossSidebarScreensAndMenu() {
        let app = designApp(["--ui-testing-large-text"])
        for destination in ["rules", "direct", "airlock", "settings"] {
            app.buttons["nav-\(destination)"].click()
            screenshot(app, "rillvia-200-percent-\(destination)")
        }
        app.terminate()
        let menu = designApp(["--ui-testing-large-text", "--ui-testing-menu-preview"])
        XCTAssertTrue(menu.buttons["menu-open-app"].waitForExistence(timeout: 3))
        screenshot(menu, "rillvia-200-percent-menu")
    }

    func testTextSizeSettingEnlargesControlsAndCanBeRestored() {
        let app = designApp()
        let originalHeight = app.buttons["fallback-picker"].frame.height
        app.buttons["nav-settings"].click()
        app.buttons["text-size-picker"].click()
        app.buttons["selector-choice-2.0"].click()
        app.buttons["nav-overview"].click()
        XCTAssertEqual(app.buttons["fallback-picker"].frame.height, originalHeight * 2, accuracy: 1)
        screenshot(app, "rillvia-real-text-size-200")
        app.buttons["nav-settings"].click()
        app.buttons["text-size-picker"].click()
        app.buttons["selector-choice-1.0"].click()
        app.buttons["nav-overview"].click()
        XCTAssertEqual(app.buttons["fallback-picker"].frame.height, originalHeight, accuracy: 1)
    }

    func testShortcutBuilderAtTwoHundredPercent() {
        let app = designApp(["--ui-testing-large-text"])
        app.buttons["nav-settings"].click()
        app.buttons["add-keyboard-shortcut"].click()
        let scope = app.buttons["shortcut-scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 3))
        XCTAssertEqual(scope.frame.height, 88, accuracy: 1)
        screenshot(app, "rillvia-shortcut-builder-200-percent")
        XCTAssertTrue(app.buttons["cancel-keyboard-shortcut"].isHittable)
        app.buttons["cancel-keyboard-shortcut"].click()
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
        XCTAssertTrue(app.descendants(matching: .any)["workspace-title"].waitForExistence(timeout: 3))
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
        let chooser = app.descendants(matching: .any)["airlock-chooser-title"]
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
            XCTAssertTrue(app.descendants(matching: .any)["airlock-chooser-title"].exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["intro-title"].waitForExistence(timeout: 3))
        screenshot(app, "rillvia-tutorial")
        for _ in 0..<5 { app.buttons["intro-done"].click() }
        XCTAssertTrue(app.descendants(matching: .any)["intro-title"].waitForNonExistence(timeout: 3))
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["keyboard-shortcuts-title"].waitForExistence(timeout: 3))
    }

    func testUpdateCheckDistinguishesNoReleaseFromAnAvailableVersion() {
        var app = designApp()
        app.buttons["nav-settings"].click()
        app.buttons["check-for-updates"].click()
        XCTAssertTrue(app.staticTexts["No published release yet."].waitForExistence(timeout: 3))
        app.terminate()
        app = designApp(["--ui-testing-update-available"])
        app.buttons["nav-settings"].click()
        app.buttons["check-for-updates"].click()
        XCTAssertTrue(app.staticTexts["Rillvia 99.0.0 is available."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["install-update"].exists)
        XCTAssertTrue(app.buttons["check-for-updates"].isEnabled)
        screenshot(app, "rillvia-update-settings")
    }

    func testDownloadedUpdateWaitsForInstallConfirmation() {
        let app = designApp(["--ui-testing-update-available", "--ui-testing-update-downloadable"])
        app.buttons["nav-settings"].click()
        app.buttons["check-for-updates"].click()
        let download = app.buttons["download-update"]
        XCTAssertTrue(download.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["install-update"].exists)
        download.click()
        let install = app.buttons["install-update"]
        XCTAssertTrue(install.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Rillvia 99.0.0 is ready to install."].exists)
        install.click()
        let later = app.sheets.firstMatch.buttons["Later"]
        XCTAssertTrue(later.waitForExistence(timeout: 3))
        screenshot(app, "rillvia-update-confirmation")
        later.click()
        XCTAssertTrue(install.isEnabled)
        XCTAssertTrue(app.staticTexts["Rillvia 99.0.0 is ready to install."].exists)
    }

    func testDarkAppearanceAtDefaultTextSize() {
        let app = designApp(["--force-dark-appearance"])
        XCTAssertTrue(app.buttons["fallback-picker"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["fallback-picker"].frame.height, 44, accuracy: 1)
        screenshot(app, "rillvia-overview-dark-default")
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
        XCTAssertTrue(app.descendants(matching: .any)["workspace-title"].waitForExistence(timeout: 5))
        screenshot(app, "rillvia-overview-dark")
        app.buttons["nav-direct"].click()
        app.buttons["browser-row-Google Chrome"].click()
        XCTAssertTrue(app.descendants(matching: .any)["browser-detail-title"].waitForExistence(timeout: 3))
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

    func testMenuPaddingSurvivesBrowserDurationAndLeaseChanges() {
        let app = designApp()
        let status = app.statusItems["Rillvia"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        status.click()
        let panel = app.dialogs.containing(.button, identifier: "menu-open-app").firstMatch
        let start = app.buttons["menu-start-temporary-browser"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        XCTAssertTrue(panel.exists)

        func checkInsets(file: StaticString = #filePath, line: UInt = #line) {
            let bounds = panel.frame
            XCTAssertEqual(bounds.width, 400, accuracy: 4, file: file, line: line)
            for element in [start, app.buttons["menu-choice-com.apple.Safari"], app.buttons["menu-choice-com.google.Chrome"], app.buttons["menu-open-app"]] {
                XCTAssertGreaterThanOrEqual(element.frame.minX - bounds.minX, 14, file: file, line: line)
                XCTAssertLessThanOrEqual(element.frame.maxX, bounds.maxX - 14, file: file, line: line)
            }
            let label = app.staticTexts["For"]
            XCTAssertGreaterThanOrEqual(label.frame.minX - bounds.minX, 14, file: file, line: line)
            XCTAssertGreaterThanOrEqual(app.radioButtons["15 min"].frame.minX - label.frame.maxX, 6, file: file, line: line)
            XCTAssertLessThanOrEqual(app.radioButtons["Until ended"].frame.maxX, bounds.maxX - 14, file: file, line: line)
        }

        checkInsets()
        for browser in ["com.apple.Safari", "company.thebrowser.dia", "com.google.Chrome"] {
            app.buttons["menu-choice-\(browser)"].click()
            for duration in ["Until ended", "30 min", "60 min", "15 min"] {
                app.radioButtons[duration].click()
                checkInsets()
            }
        }
        start.click()
        let end = app.buttons["end-temporary-browser"].firstMatch
        XCTAssertTrue(end.waitForExistence(timeout: 3))
        checkInsets()
        end.click()
        let undo = app.buttons["Undo temporary browser change"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        checkInsets()
        undo.click()
        XCTAssertTrue(end.waitForExistence(timeout: 3))
        checkInsets()

        app.buttons["menu-open-app"].click()
        status.click()
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        checkInsets()
        let attachment = XCTAttachment(screenshot: panel.screenshot())
        attachment.name = "rillvia-menu-stable-padding"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLivingBrowserHallIsStillAvailable() {
        let app = designApp()
        app.menuBars.menuBarItems["Tools"].click()
        app.menuItems["Living Browser Hall"].click()
        XCTAssertTrue(app.staticTexts["living-hall-title"].waitForExistence(timeout: 3))
        screenshot(app, "rillvia-browser-hall")
    }

    func testMenuCanSwitchRuleSetsWithoutOpeningTheWorkspace() {
        let app = designApp()
        app.typeKey("w", modifierFlags: .command)
        app.statusItems["Rillvia"].click()
        let picker = app.descendants(matching: .any).matching(identifier: "menu-rule-set-picker").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.click()
        app.menuItems["Personal"].click()
        XCTAssertEqual(picker.value as? String, "Personal")
        picker.click()
        app.menuItems["Shared rules only"].click()
        XCTAssertEqual(picker.value as? String, "Shared rules only")
        XCTAssertFalse(app.windows["Rillvia"].exists)
        let panel = app.dialogs.containing(.button, identifier: "menu-open-app").firstMatch
        let attachment = XCTAttachment(screenshot: panel.screenshot())
        attachment.name = "rillvia-menu-rule-set-picker"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func recordBrowserShortcut(in app: XCUIApplication, scope: String = "Everywhere") {
        app.buttons["nav-settings"].click()
        app.buttons["add-keyboard-shortcut"].click()
        XCTAssertTrue(app.buttons["record-shortcut"].waitForExistence(timeout: 3))
        app.buttons["record-shortcut"].click()
        app.sheets.firstMatch.typeKey("c", modifierFlags: [.control, .option, .shift])
        screenshot(app, "rillvia-shortcut-after-recording")
        XCTAssertTrue(app.buttons["save-keyboard-shortcut"].isEnabled, app.sheets.firstMatch.debugDescription)
        app.radioButtons[scope].click()
        screenshot(app, "rillvia-shortcut-builder")
        app.buttons["save-keyboard-shortcut"].click()
        XCTAssertTrue(app.buttons["record-shortcut"].waitForNonExistence(timeout: 3))
    }

    func testGlobalShortcutWorksWithAnotherAppActiveAndTheWindowClosed() {
        let app = designApp()
        recordBrowserShortcut(in: app)
        screenshot(app, "rillvia-shortcut-settings")
        app.typeKey("w", modifierFlags: .command)
        let calculator = XCUIApplication(bundleIdentifier: "com.apple.calculator")
        calculator.launch()
        defer { calculator.terminate() }
        XCTAssertTrue(calculator.windows.firstMatch.waitForExistence(timeout: 5))
        calculator.windows.firstMatch.typeKey("c", modifierFlags: [.control, .option, .shift])
        XCTAssertFalse(app.windows["Rillvia"].exists)
        app.statusItems["Rillvia"].click()
        let browser = app.staticTexts["menu-other-links-browser"]
        XCTAssertTrue(browser.waitForExistence(timeout: 3))
        XCTAssertEqual(browser.value as? String, "Google Chrome")
    }

    func testAppScopedShortcutDoesNotRunOutsideRillviaAndDeletionCanBeUndone() {
        let app = designApp()
        recordBrowserShortcut(in: app, scope: "In Rillvia")
        let calculator = XCUIApplication(bundleIdentifier: "com.apple.calculator")
        calculator.launch()
        defer { calculator.terminate() }
        XCTAssertTrue(calculator.windows.firstMatch.waitForExistence(timeout: 5))
        calculator.windows.firstMatch.typeKey("c", modifierFlags: [.control, .option, .shift])
        app.activate()
        app.buttons["nav-overview"].click()
        XCTAssertEqual(app.buttons["fallback-picker"].value as? String, "Safari")
        app.windows.firstMatch.typeKey("c", modifierFlags: [.control, .option, .shift])
        XCTAssertEqual(app.buttons["fallback-picker"].value as? String, "Google Chrome")
        app.buttons["nav-settings"].click()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "delete-shortcut-")).firstMatch.click()
        XCTAssertTrue(app.staticTexts["keyboard-shortcuts-empty"].exists)
        app.links["undo-shortcut-deletion"].click()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "edit-shortcut-")).firstMatch.exists)
    }

    func testShortcutRecorderRejectsReservedAndDuplicateKeysAndCancelKeepsActions() {
        let app = designApp()
        recordBrowserShortcut(in: app)
        app.buttons["add-keyboard-shortcut"].click()
        app.buttons["record-shortcut"].click()
        app.sheets.firstMatch.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["shortcut-validation-error"].exists)
        XCTAssertFalse(app.buttons["save-keyboard-shortcut"].isEnabled)
        app.buttons["record-shortcut"].click()
        app.sheets.firstMatch.typeKey("c", modifierFlags: [.control, .option, .shift])
        XCTAssertFalse(app.buttons["save-keyboard-shortcut"].isEnabled)
        app.buttons["cancel-keyboard-shortcut"].click()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "edit-shortcut-")).count, 1)
    }

    func testShortcutBuilderCanChooseAndRunASpecificRuleSet() {
        let app = designApp()
        app.buttons["nav-settings"].click()
        app.buttons["add-keyboard-shortcut"].click()
        app.buttons["record-shortcut"].click()
        app.sheets.firstMatch.typeKey("p", modifierFlags: [.control, .option])
        app.buttons["shortcut-action-picker"].click()
        app.buttons["selector-choice-ruleSet"].click()
        app.buttons["shortcut-rule-set-picker"].click()
        app.buttons.matching(NSPredicate(format: "label == %@", "Personal")).firstMatch.click()
        app.buttons["save-keyboard-shortcut"].click()
        app.typeKey("p", modifierFlags: [.control, .option])
        app.buttons["nav-overview"].click()
        XCTAssertEqual(app.buttons["active-rule-set-picker"].value as? String, "Personal")
    }

    func testIncomingURLLaunchRemainsWindowless() {
        let app = launch(["--ui-testing-routing-fixture", "--ui-testing-incoming-fallback"])
        XCTAssertFalse(app.windows.firstMatch.waitForExistence(timeout: 3))
    }

    func testIncomingURLLeavesAnOpenWindowInPlace() {
        let app = launch(["--ui-testing-routing-fixture", "--ui-testing-incoming-while-open"])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        // The link arrives 2.5 s after launch; the window the person opened must survive it.
        XCTAssertFalse(window.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["workspace-title"].exists)
    }
}
