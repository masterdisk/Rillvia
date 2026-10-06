import AppKit
import XCTest
@testable import BrowserChange

@MainActor
final class KeyboardShortcutTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var directory: URL!
    private var repository: StateRepository!
    private var handler: FakeSystemBrowserHandler!
    private var shortcuts: KeyboardShortcutStore!
    private let safari = InstalledBrowser(id: "com.apple.Safari", name: "Safari", version: "26", appURL: URL(fileURLWithPath: "/Applications/Safari.app"))
    private let chrome = InstalledBrowser(id: "com.google.Chrome", name: "Google Chrome", version: "140", appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"))
    private let work = RoutingProfile(name: "Work")
    private let personal = RoutingProfile(name: "Personal")

    override func setUpWithError() throws {
        suite = "Rillvia-ShortcutTests-\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        shortcuts = KeyboardShortcutStore(defaults: defaults)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        repository = StateRepository(baseDirectory: directory)
        let selfBrowser = BrowserReference(bundleIdentifier: "com.browserchange.BrowserChange")
        handler = FakeSystemBrowserHandler(handlers: .same(HandlerApplication(browser: selfBrowser, applicationURL: Bundle.main.bundleURL)), applications: [selfBrowser: Bundle.main.bundleURL, safari.reference: safari.appURL, chrome.reference: chrome.appURL])
        try repository.saveConfiguration(RoutingConfiguration(mode: .smart, fallbackBrowser: safari.reference,
            domainRules: [DomainRule(domain: "github.com", browser: chrome.reference, profileID: work.id), DomainRule(domain: "github.com", browser: safari.reference, profileID: personal.id)], profiles: [work, personal], activeProfileID: work.id))
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
    private func store() -> BrowserStore {
        BrowserStore(services: BrowserChangeServices(environment: AppEnvironment(browserCatalog: FakeBrowserCatalog(browsers: [safari, chrome]), systemBrowserHandler: handler, stateRepository: repository, urlLauncher: FakeURLLauncher())), shortcuts: shortcuts)
    }
    private func binding(_ action: ShortcutAction = ShortcutAction(kind: .useBrowser, browserID: "com.google.Chrome"), scope: ShortcutScope = .everywhere) -> ShortcutBinding {
        ShortcutBinding(chord: ShortcutChord(keyCode: 8, modifiers: [.control, .option], key: "C"), scope: scope, action: action)
    }

    func testBindingSurvivesReloadWithActionArgumentsAndScope() {
        let original = binding(ShortcutAction(kind: .temporaryBrowser, browserID: chrome.id, duration: .sixtyMinutes), scope: .rillvia)
        XCTAssertNil(shortcuts.save(original))
        let reloaded = KeyboardShortcutStore(defaults: defaults)
        XCTAssertEqual(reloaded.bindings, [original])
        XCTAssertNil(shortcuts.setEnabled(false, id: original.id))
        XCTAssertFalse(KeyboardShortcutStore(defaults: defaults).bindings[0].isEnabled)
    }

    func testTypingAndBuiltInCommandsCannotBeCapturedAsActions() {
        for chord in [ShortcutChord(keyCode: 8, modifiers: [], key: "C"), ShortcutChord(keyCode: 37, modifiers: .command, key: "L"), ShortcutChord(keyCode: 45, modifiers: .command, key: "N"), ShortcutChord(keyCode: 18, modifiers: .command, key: "1")] {
            var invalid = binding(); invalid.chord = chord
            XCTAssertNotNil(shortcuts.save(invalid))
        }
        XCTAssertTrue(shortcuts.bindings.isEmpty)
        XCTAssertNil(defaults.data(forKey: KeyboardShortcutStore.preferencesKey))
    }

    func testDuplicatePhysicalKeysConflictAcrossScopesAndEnableChecks() {
        let original = binding()
        XCTAssertNil(shortcuts.save(original))
        var duplicate = binding(scope: .rillvia)
        duplicate.chord?.key = "c"
        XCTAssertNotNil(shortcuts.save(duplicate))
        duplicate.isEnabled = false
        XCTAssertNil(shortcuts.save(duplicate))
        XCTAssertNotNil(shortcuts.setEnabled(true, id: duplicate.id))
        XCTAssertFalse(shortcuts.bindings[1].isEnabled)
        XCTAssertNil(shortcuts.setEnabled(false, id: original.id))
        XCTAssertNil(shortcuts.setEnabled(true, id: duplicate.id))
    }

    func testDeleteAndUndoPersistAndReleaseTheKeys() {
        let original = binding()
        XCTAssertNil(shortcuts.save(original))
        shortcuts.remove(original.id)
        XCTAssertTrue(KeyboardShortcutStore(defaults: defaults).bindings.isEmpty)
        XCTAssertTrue(shortcuts.canUndoRemoval)
        XCTAssertNil(shortcuts.undoRemoval())
        XCTAssertEqual(KeyboardShortcutStore(defaults: defaults).bindings, [original])
    }

    func testUnreadablePreferencesArePreservedUntilExplicitReset() {
        let unknown = Data(#"{"version":99,"bindings":[]}"#.utf8)
        defaults.set(unknown, forKey: KeyboardShortcutStore.preferencesKey)
        let unreadable = KeyboardShortcutStore(defaults: defaults)
        XCTAssertNotNil(unreadable.loadError)
        XCTAssertNotNil(unreadable.save(binding()))
        XCTAssertEqual(defaults.data(forKey: KeyboardShortcutStore.preferencesKey), unknown)
        unreadable.resetUnreadable()
        XCTAssertNil(unreadable.loadError)
        XCTAssertEqual(defaults.data(forKey: KeyboardShortcutStore.preferencesKey + ".backup"), unknown)
        XCTAssertNil(unreadable.save(binding()))
    }

    func testRuleSetActionsChangeRoutingWithoutChangingHandlersOrDrafts() async throws {
        let store = store(); await store.activate()
        store.workspace.startRule(browserID: chrome.id, profileID: work.id)
        store.workspace.draft?.domain = "unfinished.example"
        let draft = store.workspace.draft
        let switched = await ShortcutExecutor.run(ShortcutAction(kind: .ruleSet, ruleSetID: personal.id.uuidString), in: store, openApp: {})
        XCTAssertNil(switched)
        XCTAssertEqual(store.routingConfiguration.activeProfileID, personal.id)
        XCTAssertEqual(store.workspace.draft, draft)
        store.stageAirlock(text: "https://github.com/openai")
        XCTAssertEqual(store.prediction(for: try XCTUnwrap(store.airlockResult.items.first))?.target, safari.reference)
        let shared = await ShortcutExecutor.run(ShortcutAction(kind: .nextRuleSet), in: store, openApp: {})
        XCTAssertNil(shared)
        XCTAssertNil(store.routingConfiguration.activeProfileID)
        let next = await ShortcutExecutor.run(ShortcutAction(kind: .nextRuleSet), in: store, openApp: {})
        XCTAssertNil(next)
        XCTAssertEqual(store.routingConfiguration.activeProfileID, work.id)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testBrowserActionChangesOtherLinksAndPreservesTheActiveSet() async {
        let store = store(); await store.activate()
        let problem = await ShortcutExecutor.run(binding().action, in: store, openApp: {})
        XCTAssertNil(problem)
        XCTAssertEqual(store.smartFallbackBrowser?.id, chrome.id)
        XCTAssertEqual(store.routingConfiguration.activeProfileID, work.id)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testBrowserActionUsesTheMacOSHandlerInDirectMode() async throws {
        try repository.saveConfiguration(.fresh)
        handler.handlers = .same(HandlerApplication(browser: safari.reference, applicationURL: safari.appURL))
        let store = store(); await store.activate()
        let problem = await ShortcutExecutor.run(binding().action, in: store, openApp: {})
        XCTAssertNil(problem)
        XCTAssertEqual(handler.handlers.health(browserChange: BrowserReference(bundleIdentifier: "com.browserchange.BrowserChange")).agreedExternalBrowser, chrome.reference)
        XCTAssertEqual(handler.setCalls.count, 2)
    }

    func testMissingTargetsDoNotFallBackOrMutateSettings() async {
        let store = store(); await store.activate()
        let before = store.routingConfiguration
        for action in [ShortcutAction(kind: .useBrowser, browserID: "missing.browser"), ShortcutAction(kind: .ruleSet, ruleSetID: UUID().uuidString), ShortcutAction(kind: .ruleSet, ruleSetID: "not-an-id")] {
            let problem = await ShortcutExecutor.run(action, in: store, openApp: {})
            XCTAssertNotNil(problem)
        }
        XCTAssertEqual(store.routingConfiguration, before)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testTemporaryActionEndsAndRespectsAnExternalHandlerChange() async {
        let store = store(); await store.activate()
        let started = await ShortcutExecutor.run(ShortcutAction(kind: .temporaryBrowser, browserID: chrome.id, duration: .thirtyMinutes), in: store, openApp: {})
        XCTAssertNil(started)
        XCTAssertEqual(store.activeLeaseBrowser?.id, chrome.id)
        let ended = await ShortcutExecutor.run(ShortcutAction(kind: .endTemporaryBrowser), in: store, openApp: {})
        XCTAssertNil(ended)
        XCTAssertNil(store.activeBrowserLease)
        handler.handlers = .same(HandlerApplication(browser: safari.reference, applicationURL: safari.appURL))
        let suspended = await ShortcutExecutor.run(ShortcutAction(kind: .temporaryBrowser, browserID: chrome.id), in: store, openApp: {})
        XCTAssertNotNil(suspended)
        XCTAssertNil(store.activeBrowserLease)
        XCTAssertTrue(handler.setCalls.isEmpty)
    }

    func testRegistrationConflictsPauseEditingAndUnregisterDisabledActions() {
        let store = store()
        let registry = FakeHotKeyRegistry()
        let controller = KeyboardShortcutController(store: store, registry: registry, openApp: {})
        defer { controller.stop() }
        let original = binding()
        registry.reject = true
        XCTAssertNotNil(shortcuts.save(original))
        XCTAssertTrue(shortcuts.bindings.isEmpty)
        registry.reject = false
        XCTAssertNil(shortcuts.save(original))
        XCTAssertEqual(Set(registry.registered.keys), [original.id])
        shortcuts.isEditing = true
        XCTAssertTrue(registry.registered.isEmpty)
        shortcuts.isEditing = false
        XCTAssertEqual(Set(registry.registered.keys), [original.id])
        XCTAssertNil(shortcuts.setEnabled(false, id: original.id))
        XCTAssertTrue(registry.registered.isEmpty)
        XCTAssertNil(shortcuts.setEnabled(true, id: original.id))
        XCTAssertEqual(Set(registry.registered.keys), [original.id])
    }
}

@MainActor
private final class FakeHotKeyRegistry: HotKeyRegistering {
    var onPress: ((UUID) -> Void)?
    var registered: [UUID: ShortcutChord] = [:]
    var reject = false
    func register(_ id: UUID, chord: ShortcutChord) -> Bool {
        guard !reject, !registered.values.contains(where: { $0.fingerprint == chord.fingerprint }) else { return false }
        registered[id] = chord; return true
    }
    func unregister(_ id: UUID) { registered.removeValue(forKey: id) }
    func removeAll() { registered.removeAll() }
}
