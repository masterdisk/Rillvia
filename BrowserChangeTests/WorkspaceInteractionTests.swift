import AppKit
import Foundation
import XCTest
@testable import BrowserChange

@MainActor
final class WorkspaceInteractionTests: XCTestCase {
    private let safari = InstalledBrowser(id: "com.apple.Safari", name: "Safari", version: "26", appURL: URL(fileURLWithPath: "/Applications/Safari.app"))
    private let chrome = InstalledBrowser(id: "com.google.Chrome", name: "Google Chrome", version: "140", appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"))
    private let selfBrowser = BrowserReference(bundleIdentifier: "com.browserchange.BrowserChange")
    private var directory: URL!
    private var repository: StateRepository!
    private var launcher: FakeURLLauncher!
    private var handler: FakeSystemBrowserHandler!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RillviaInteractions-\(UUID())")
        repository = StateRepository(baseDirectory: directory)
        launcher = FakeURLLauncher()
        handler = FakeSystemBrowserHandler(handlers: .same(HandlerApplication(browser: selfBrowser, applicationURL: Bundle.main.bundleURL)), applications: [selfBrowser: Bundle.main.bundleURL, safari.reference: safari.appURL, chrome.reference: chrome.appURL])
        try repository.saveConfiguration(RoutingConfiguration(mode: .smart, fallbackBrowser: safari.reference))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }
    private func store() -> BrowserStore {
        BrowserStore(environment: AppEnvironment(browserCatalog: FakeBrowserCatalog(browsers: [safari, chrome]), systemBrowserHandler: handler, stateRepository: repository, urlLauncher: launcher))
    }

    func testBuiltAppIncludesItsBrandAssetsAndTemplateMenuGlyph() throws {
        XCTAssertNotNil(Bundle.main.url(forResource: "Assets", withExtension: "car"))
        XCTAssertNotNil(Bundle.main.image(forResource: "AppLogo"))
        let iconName = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String)
        XCTAssertNotNil(Bundle.main.url(forResource: iconName, withExtension: iconName.hasSuffix(".icns") ? nil : "icns"))
        let glyph = try XCTUnwrap(AppBrand.menuImage)
        XCTAssertTrue(glyph.isTemplate)
        XCTAssertGreaterThan(glyph.size.width, 0)
    }

    func testDirtyNavigationWaitsForAnExplicitDiscardAndCancelKeepsDraft() {
        let model = WorkspaceModel()
        let rule = DomainRule(domain: "example.com", browser: safari.reference)
        model.load(rule)
        model.draft?.domain = "changed.example.com"
        var navigated = false
        model.request { navigated = true }
        XCTAssertFalse(navigated)
        XCTAssertTrue(model.showDiscardChanges)
        model.keepEditing()
        XCTAssertEqual(model.draft?.domain, "changed.example.com")
        model.request { navigated = true }
        model.discardAndContinue()
        XCTAssertTrue(navigated)
        XCTAssertEqual(model.draft, model.savedDraft)
    }

    func testPreviewCannotOpenAfterInputChanges() async throws {
        let store = store()
        await store.activate()
        store.workspace.previewInput = "https://example.com/original"
        store.stageAirlock(text: store.workspace.previewInput)
        store.workspace.markPreview(input: store.workspace.previewInput, revision: store.revision)
        let item = try XCTUnwrap(store.airlockResult.items.first)
        let decision = try XCTUnwrap(store.prediction(for: item))
        let revision = store.revision
        store.workspace.previewInput = "https://example.com/changed"
        _ = await store.openPreview(item, expected: decision, revision: revision)
        XCTAssertTrue(launcher.calls.isEmpty)
    }

    func testPreviewCannotOpenAfterRoutingChanges() async throws {
        let store = store()
        await store.activate()
        store.workspace.previewInput = "https://example.com"
        store.stageAirlock(text: store.workspace.previewInput)
        store.workspace.markPreview(input: store.workspace.previewInput, revision: store.revision)
        let item = try XCTUnwrap(store.airlockResult.items.first)
        let decision = try XCTUnwrap(store.prediction(for: item))
        let revision = store.revision
        await store.makeDefault(chrome)
        _ = await store.openPreview(item, expected: decision, revision: revision)
        XCTAssertTrue(launcher.calls.isEmpty)
    }

    func testAValidPreviewOpensTheOriginalURLInThePredictedBrowser() async throws {
        let store = store()
        await store.activate()
        store.workspace.previewInput = "https://example.com/path?utm_source=mail#section"
        store.stageAirlock(text: store.workspace.previewInput)
        store.workspace.markPreview(input: store.workspace.previewInput, revision: store.revision)
        let item = try XCTUnwrap(store.airlockResult.items.first)
        let decision = try XCTUnwrap(store.prediction(for: item))
        let outcome = await store.openPreview(item, expected: decision, revision: store.revision)
        XCTAssertEqual(outcome, .opened(safari.reference))
        XCTAssertEqual(launcher.calls.first?.url.absoluteString, store.workspace.previewInput)
        XCTAssertEqual(launcher.calls.first?.browser, safari.reference)
    }

    func testDirectPreviewUsesCurrentMacOSHandlerWithoutChangingIt() throws {
        try repository.saveConfiguration(.fresh)
        handler.handlers = .same(HandlerApplication(browser: chrome.reference, applicationURL: chrome.appURL))
        let store = store()
        store.stageAirlock(text: "https://example.com")
        let item = try XCTUnwrap(store.airlockResult.items.first)
        XCTAssertEqual(store.prediction(for: item)?.target, chrome.reference)
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertTrue(launcher.calls.isEmpty)
    }

    func testPausedRoutingDisplaysTheMacOSBrowserAndPreservesTheSavedChoice() async throws {
        handler.handlers = .same(HandlerApplication(browser: chrome.reference, applicationURL: chrome.appURL))
        let store = store()
        await store.activate()
        XCTAssertTrue(store.isSmartRoutingConfigured)
        XCTAssertFalse(store.isSmartRoutingActive)
        XCTAssertEqual(store.smartFallbackBrowser?.reference, safari.reference)
        XCTAssertEqual(store.defaultBundleID, safari.id)
        XCTAssertEqual(store.currentMacOSBrowser?.reference, chrome.reference)
        XCTAssertEqual(store.currentMacOSBrowserName, "Google Chrome")
        store.stageAirlock(text: "https://example.com")
        let item = try XCTUnwrap(store.airlockResult.items.first)
        XCTAssertEqual(store.prediction(for: item)?.target, chrome.reference)
        XCTAssertEqual(try repository.loadConfiguration().fallbackBrowser, safari.reference)
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertTrue(launcher.calls.isEmpty)
    }

    func testPausedPreviewFollowsTheHandlerForEachURLScheme() async throws {
        handler.handlers = HTTPHandlerSnapshot(
            http: HandlerApplication(browser: chrome.reference, applicationURL: chrome.appURL),
            https: HandlerApplication(browser: safari.reference, applicationURL: safari.appURL)
        )
        let store = store()
        await store.activate()
        XCTAssertFalse(store.isSmartRoutingActive)
        XCTAssertEqual(store.currentMacOSBrowserName, "HTTP and HTTPS differ")
        for (url, browser) in [("http://example.com", chrome.reference), ("https://example.com", safari.reference)] {
            store.stageAirlock(text: url)
            let item = try XCTUnwrap(store.airlockResult.items.first)
            XCTAssertEqual(store.prediction(for: item)?.target, browser)
        }
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertTrue(launcher.calls.isEmpty)
    }

    func testDeletedRuleCanBeRestoredWithoutChangingSystemHandlers() throws {
        let store = store()
        let rule = try XCTUnwrap(store.createRule(domain: "example.com", browser: chrome.reference))
        XCTAssertTrue(store.deleteRule(rule.id))
        XCTAssertTrue(store.canUndoConfiguration)
        XCTAssertTrue(store.undoConfigurationChange())
        XCTAssertEqual(store.routingConfiguration.domainRules, [rule])
        XCTAssertTrue(handler.setCalls.isEmpty)
        XCTAssertTrue(launcher.calls.isEmpty)
    }

    func testConfigurationUndoDoesNotOverwriteANewerTemporaryBrowser() async throws {
        let store = store()
        await store.activate()
        _ = store.createRule(domain: "example.com", browser: chrome.reference)
        XCTAssertTrue(store.canUndoConfiguration)
        XCTAssertTrue(store.borrowBrowser(chrome, for: .fifteenMinutes))
        XCTAssertFalse(store.canUndoConfiguration)
        XCTAssertFalse(store.undoConfigurationChange())
        XCTAssertEqual(store.activeLeaseBrowser?.reference, chrome.reference)
    }

    func testDeletingTheBrowsedSetClearsItsEditorAndUndoRestoresItsRules() throws {
        let store = store()
        let profile = try XCTUnwrap(store.createProfile(named: "Work"))
        let rule = try XCTUnwrap(store.createRule(domain: "example.com", browser: chrome.reference, profileID: profile.id))
        store.workspace.browsedProfileID = profile.id
        store.workspace.load(rule)
        XCTAssertTrue(store.deleteProfile(profile.id))
        XCTAssertNil(store.workspace.browsedProfileID)
        XCTAssertNil(store.workspace.draft)
        XCTAssertFalse(store.workspace.hasUnsavedRule)
        XCTAssertTrue(store.undoConfigurationChange())
        XCTAssertTrue(store.routingConfiguration.profiles.contains(where: { $0.id == profile.id }))
        XCTAssertTrue(store.routingConfiguration.domainRules.contains(rule))
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testPrivateOpenNeverPersistsAStandardRuleWhenTeachingIsRequested() async throws {
        let store = store()
        await store.activate()
        store.stageAirlock(text: "https://example.com")
        let item = try XCTUnwrap(store.airlockResult.items.first)
        let result = await store.openAirlockFromChooser(item, in: chrome.reference, always: .exactHost, launch: .privateWindow)
        XCTAssertEqual(result.routingOutcome, .opened(chrome.reference))
        XCTAssertFalse(result.teachingSucceeded)
        XCTAssertFalse(result.shouldDismiss)
        XCTAssertEqual(launcher.calls.first?.launch, .privateWindow)
        XCTAssertTrue(try repository.loadConfiguration().domainRules.isEmpty)
    }

    func testNewDisabledRuleIsPersistedAsDisabledInOneUndoableChange() throws {
        let store = store()
        let rule = try XCTUnwrap(store.createRule(domain: "example.com", browser: chrome.reference, isEnabled: false))
        XCTAssertFalse(rule.isEnabled)
        XCTAssertFalse(try XCTUnwrap(repository.loadConfiguration().domainRules.first).isEnabled)
        XCTAssertTrue(store.undoConfigurationChange())
        XCTAssertTrue(store.routingConfiguration.domainRules.isEmpty)
    }
}
