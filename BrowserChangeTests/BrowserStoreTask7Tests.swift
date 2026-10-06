import AppKit
import Foundation
import XCTest
@testable import BrowserChange

@MainActor
final class BrowserStoreTask7Tests: XCTestCase {
    private let browserChange = InstalledBrowser(
        id: "com.browserchange.BrowserChange",
        name: "BrowserChange",
        version: "1",
        appURL: URL(
            fileURLWithPath: "/Applications/BrowserChange.app"
        )
    )
    private let chrome = InstalledBrowser(
        id: "com.google.Chrome",
        name: "Google Chrome",
        version: "140",
        appURL: URL(
            fileURLWithPath: "/Applications/Google Chrome.app"
        )
    )
    private let safari = InstalledBrowser(
        id: "com.apple.Safari",
        name: "Safari",
        version: "26",
        appURL: URL(fileURLWithPath: "/Applications/Safari.app")
    )

    private var directory: URL!
    private var repository: StateRepository!
    private var launcher: FakeURLLauncher!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BrowserStoreTask7Tests-\(UUID().uuidString)"
            )
        repository = StateRepository(baseDirectory: directory)
        launcher = FakeURLLauncher()
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            )
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testFailedAlwaysOpenPersistenceKeepsChooserOpenWithActionableError() async throws {
        let store = makeStore()
        await store.activate()
        store.stageAirlock(
            text: "https://example.com/private?secret=value"
        )
        let item = try XCTUnwrap(store.airlockResult.items.first)
        try poisonHistoryWithFutureSchema()

        let result = await store.openAirlockFromChooser(
            item,
            in: safari.reference,
            always: .exactHost,
            profileID: nil
        )

        XCTAssertEqual(
            result.routingOutcome,
            .opened(safari.reference)
        )
        XCTAssertFalse(result.shouldDismiss)
        XCTAssertEqual(
            result.errorMessage,
            "The link opened in Safari, but the “Always open” rule was not saved. Reopen Rillvia, then try again."
        )
        XCTAssertEqual(store.message, result.errorMessage)
        XCTAssertTrue(
            try repository.loadConfiguration().domainRules.isEmpty
        )
        XCTAssertEqual(launcher.calls.count, 1)
    }

    func testSuccessfulAlwaysOpenTeachingAllowsChooserDismissal() async throws {
        let store = makeStore()
        await store.activate()
        store.stageAirlock(text: "https://example.com/path")
        let item = try XCTUnwrap(store.airlockResult.items.first)

        let result = await store.openAirlockFromChooser(
            item,
            in: safari.reference,
            always: .includeSubdomains,
            profileID: nil
        )

        XCTAssertEqual(
            result.routingOutcome,
            .opened(safari.reference)
        )
        XCTAssertTrue(result.shouldDismiss)
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(
            try repository.loadConfiguration()
                .domainRules.first?.scope,
            .includeSubdomains
        )
    }

    func testDisappearedExplicitTargetKeepsChooserOpenWithoutLaunching() async throws {
        let catalog = FakeBrowserCatalog(
            browsers: [chrome, safari]
        )
        let store = makeStore(catalog: catalog)
        await store.activate()
        store.stageAirlock(text: "https://example.com/target-gone")
        let item = try XCTUnwrap(store.airlockResult.items.first)
        catalog.browsers = [chrome]

        let result = await store.openAirlockFromChooser(
            item,
            in: safari.reference
        )

        XCTAssertEqual(
            result.routingOutcome,
            .rejected(
                .explicitTargetUnavailable(safari.reference)
            )
        )
        XCTAssertFalse(result.shouldDismiss)
        XCTAssertTrue(launcher.calls.isEmpty)
        XCTAssertEqual(
            result.errorMessage,
            "The selected browser is no longer available. Reinstall it or choose another browser."
        )
        XCTAssertEqual(store.message, result.errorMessage)
    }

    func testDiagnosticsUsesLiveStateButNeverIncludesAirlockURL() async {
        let store = makeStore()
        await store.activate()
        store.stageAirlock(
            text: "https://secret.example/private?token=clipboard-secret"
        )

        store.openDiagnostics()
        let text = store.diagnosticsSnapshot.visibleText

        XCTAssertTrue(store.showDiagnostics)
        XCTAssertTrue(
            text.contains(
                "HTTPS: com.browserchange.BrowserChange — BrowserChange"
            )
        )
        XCTAssertTrue(
            text.contains(
                "External fallback: Google Chrome (com.google.Chrome)"
            )
        )
        XCTAssertFalse(text.contains("secret.example"))
        XCTAssertFalse(text.contains("/private"))
        XCTAssertFalse(text.contains("clipboard-secret"))
    }

    func testDiagnosticsReportsLeaseUndoAvailability() async {
        let store = makeStore()
        await store.activate()
        XCTAssertTrue(
            store.borrowBrowser(
                safari,
                for: .fifteenMinutes
            )
        )
        XCTAssertTrue(store.canUndoLease)

        XCTAssertTrue(
            store.diagnosticsSnapshot.visibleText.contains(
                "Undo available: Yes"
            )
        )
    }

    func testHiddenSurfacesNeverQuarantineOrRewriteCorruptState() throws {
        let store = makeStore()
        try Data("not-json-journal".utf8).write(
            to: directory.appendingPathComponent(
                "handler-journal.json"
            )
        )
        try Data("not-json-history".utf8).write(
            to: directory.appendingPathComponent(
                "configuration-history.json"
            )
        )
        let before = try persistedFiles()

        store.openDiagnostics()
        _ = store.diagnosticsSnapshot
        store.openTimeMachine()

        XCTAssertEqual(try persistedFiles(), before)
        XCTAssertFalse(
            try persistedFiles().keys.contains {
                $0.contains(".corrupt-")
            }
        )
    }

    func testHistoricalEvaluationPerformsNoLaunchOrPersistenceWrite() throws {
        let historical = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari.reference,
            domainRules: [
                DomainRule(
                    domain: "example.com",
                    browser: BrowserReference(
                        bundleIdentifier: "org.mozilla.firefox"
                    )
                ),
            ]
        )
        try repository.appendConfigurationSnapshot(
            historical,
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let store = makeStore()
        let before = try persistedFiles()

        store.openTimeMachine()
        let snapshotID = try XCTUnwrap(
            store.timeMachineModel.snapshots.first?.id
        )
        let evaluation = store.evaluateHistoricalURL(
            "https://example.com/private?secret=value",
            snapshotID: snapshotID
        )

        XCTAssertTrue(store.showTimeMachine)
        XCTAssertEqual(evaluation.target, safari.reference)
        XCTAssertEqual(
            evaluation.reason,
            "Your usual browser"
        )
        XCTAssertTrue(launcher.calls.isEmpty)
        XCTAssertEqual(try persistedFiles(), before)
        XCTAssertFalse(
            try persistedText().contains("/private?secret=value")
        )

        store.returnToNow()
        XCTAssertFalse(store.showTimeMachine)
    }

    func testHallAndLegacyGatesRemainDeterministic() {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 1_900_000_000)

        for index in 0..<4 {
            store.tapTitle(
                at: start.addingTimeInterval(Double(index) * 0.1)
            )
            XCTAssertFalse(store.showHall)
        }
        store.tapTitle(at: start.addingTimeInterval(0.4))
        XCTAssertTrue(store.showHall)

        let hall = store.livingHallModel
        XCTAssertEqual(
            hall.eras.filter(\.isRepresented).map(\.name),
            ["Safari", "Chrome"]
        )
        XCTAssertEqual(
            hall.browsers.first {
                $0.id == chrome.id
            }?.status,
            ["Browser for sites with no rule"]
        )

        for index in 0..<4 {
            store.tapMoon(
                at: start.addingTimeInterval(Double(index) * 0.1)
            )
        }
        XCTAssertEqual(
            store.message,
            "The browsers logged off. You do not have to."
        )

        for (index, character) in ["l", "y", "n", "x"].enumerated() {
            store.noteTyping(
                character,
                at: start.addingTimeInterval(Double(index) * 0.1)
            )
        }
        XCTAssertEqual(store.browsers.last?.name, "Lynx")
    }

    func testRoutingSummaryTimeMachineTriggerRequiresOptionModifier() {
        XCTAssertFalse(
            RoutingSummaryTrigger.opensTimeMachine(
                for: []
            )
        )
        XCTAssertFalse(
            RoutingSummaryTrigger.opensTimeMachine(
                for: [.command]
            )
        )
        XCTAssertTrue(
            RoutingSummaryTrigger.opensTimeMachine(
                for: [.option]
            )
        )
        XCTAssertTrue(
            RoutingSummaryTrigger.opensTimeMachine(
                for: [.option, .shift]
            )
        )
    }

    func testMotionPolicyDisablesTransitionsForSystemOrTestReduction() {
        XCTAssertTrue(
            BrowserChangeMotionPolicy.animationsEnabled(
                systemReduceMotion: false,
                testingOverride: false
            )
        )
        XCTAssertFalse(
            BrowserChangeMotionPolicy.animationsEnabled(
                systemReduceMotion: true,
                testingOverride: false
            )
        )
        XCTAssertFalse(
            BrowserChangeMotionPolicy.animationsEnabled(
                systemReduceMotion: false,
                testingOverride: true
            )
        )
    }

    func testColdLaunchQueuedURLDrainsOnlyAfterStorePreparation() async throws {
        let queue = IncomingURLQueue()
        let delegate = AppDelegate(incomingURLQueue: queue)
        let url = try XCTUnwrap(
            URL(string: "https://example.com/cold-launch")
        )

        delegate.application(NSApplication.shared, open: [url])
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertTrue(launcher.calls.isEmpty)

        let store = makeStore()
        delegate.connect(store: store, openMainWindow: {})
        await delegate.prepareForIncomingURLs()

        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(
            launcher.calls,
            [.init(url: url, browser: chrome.reference)]
        )
    }

    func testDisappearedRuleTargetFallsThroughToInstalledFallback() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                domainRules: [
                    DomainRule(
                        domain: "example.com",
                        browser: safari.reference
                    ),
                ]
            )
        )
        let store = makeStore(browsers: [chrome])
        await store.activate()
        let url = try XCTUnwrap(
            URL(string: "https://example.com/target-gone")
        )

        let disposition = await store.routeIncomingURL(url)

        XCTAssertEqual(disposition, .consumed)
        XCTAssertEqual(
            launcher.calls,
            [.init(url: url, browser: chrome.reference)]
        )
    }

    func testDuplicateBounceIsConsumedWithoutSecondLaunch() async throws {
        let store = makeStore()
        await store.activate()
        let url = try XCTUnwrap(
            URL(string: "https://example.com/bounce")
        )

        let first = await store.routeIncomingURL(url)
        let duplicate = await store.routeIncomingURL(url)

        XCTAssertEqual(first, .consumed)
        XCTAssertEqual(duplicate, .consumed)

        XCTAssertEqual(launcher.calls.count, 1)
        XCTAssertEqual(
            store.message,
            "Rillvia stopped a repeated link."
        )
    }

    func testExpiryPersistenceFailureNeverRoutesThroughExpiredLease() async throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                browserLease: BrowserLease(
                    browser: safari.reference,
                    startedAt: now.addingTimeInterval(-901),
                    expiresAt: now
                )
            )
        )
        try poisonHistoryWithFutureSchema()
        let store = makeStore(now: { now })
        await store.activate()
        let url = try XCTUnwrap(
            URL(string: "https://example.com/expired")
        )

        let disposition = await store.routeIncomingURL(url)

        XCTAssertEqual(disposition, .consumed)
        XCTAssertEqual(
            launcher.calls,
            [.init(url: url, browser: chrome.reference)]
        )
        XCTAssertNotNil(
            try repository.loadConfiguration().browserLease,
            "The failed persistence attempt must not pretend the lease was removed."
        )
        XCTAssertEqual(
            store.message,
            "Rillvia could not check the temporary browser. Expired ones will not be used."
        )
    }

    private func makeStore(
        browsers: [InstalledBrowser]? = nil,
        catalog: FakeBrowserCatalog? = nil,
        now: @escaping () -> Date = Date.init
    ) -> BrowserStore {
        let handler = FakeSystemBrowserHandler(
            handlers: .same(
                HandlerApplication(
                    browser: browserChange.reference,
                    applicationURL: browserChange.appURL
                )
            ),
            applications: [
                browserChange.reference: browserChange.appURL,
                chrome.reference: chrome.appURL,
                safari.reference: safari.appURL,
            ]
        )
        let catalog = catalog ?? FakeBrowserCatalog(
            browsers: browsers ?? [chrome, safari]
        )
        return BrowserStore(
            environment: AppEnvironment(
                browserCatalog: catalog,
                systemBrowserHandler: handler,
                stateRepository: repository,
                urlLauncher: launcher,
                now: now
            )
        )
    }

    private func poisonHistoryWithFutureSchema() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data(
            #"{"schemaVersion":999,"entries":[]}"#.utf8
        ).write(
            to: directory.appendingPathComponent(
                "configuration-history.json"
            )
        )
    }

    private func persistedFiles() throws -> [String: Data] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return [:]
        }
        return try Dictionary(
            uniqueKeysWithValues: FileManager.default
                .contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )
                .map {
                    ($0.lastPathComponent, try Data(contentsOf: $0))
                }
        )
    }

    private func persistedText() throws -> String {
        try persistedFiles().values.map {
            String(decoding: $0, as: UTF8.self)
        }
        .joined(separator: "\n")
    }
}
