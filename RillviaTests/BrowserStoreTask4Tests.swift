import Foundation
import XCTest
@testable import Rillvia

@MainActor
final class BrowserStoreTask4Tests: XCTestCase {
    private let rillvia = InstalledBrowser(
        id: "com.rillvia.app",
        name: "Rillvia",
        version: "1",
        appURL: URL(fileURLWithPath: "/Applications/Rillvia.app")
    )
    private let chrome = InstalledBrowser(
        id: "com.google.Chrome",
        name: "Google Chrome",
        version: "140",
        appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
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
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BrowserStoreTask4Tests-\(UUID().uuidString)"
        )
        repository = StateRepository(baseDirectory: directory)
        launcher = FakeURLLauncher()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testStagingAirlockPreviewsWithoutLaunchingAndOpenNowUsesPrediction() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                domainRules: [
                    DomainRule(domain: "example.com", browser: safari.reference),
                ]
            )
        )
        let store = makeStore()
        await store.activate()
        let original = "https://example.com/private/path?secret=value"

        store.stageAirlock(text: original)

        XCTAssertTrue(launcher.calls.isEmpty)
        let item = try XCTUnwrap(store.airlockResult.items.first)
        XCTAssertEqual(
            store.prediction(for: item)?.target,
            safari.reference
        )

        let outcome = await store.openAirlockNow(item)

        XCTAssertEqual(outcome, .opened(safari.reference))
        XCTAssertEqual(
            launcher.calls,
            [
                .init(
                    url: try XCTUnwrap(URL(string: original)),
                    browser: safari.reference
                ),
            ]
        )
        XCTAssertFalse(try persistedText().contains("/private/path"))
        XCTAssertFalse(try persistedText().contains("secret=value"))
    }

    func testExplicitOpenCanTeachAnIncludeSubdomainsRule() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            )
        )
        let store = makeStore()
        await store.activate()
        store.stageAirlock(
            text: "https://Docs.Example.com./private?utm_source=mail"
        )
        let item = try XCTUnwrap(store.airlockResult.items.first)

        let outcome = await store.openAirlock(
            item,
            in: safari.reference,
            always: .includeSubdomains,
            profileID: nil
        )

        XCTAssertEqual(outcome, .opened(safari.reference))
        let saved = try repository.loadConfiguration()
        XCTAssertEqual(saved.domainRules.count, 1)
        XCTAssertEqual(saved.domainRules[0].domain, "docs.example.com")
        XCTAssertEqual(saved.domainRules[0].scope, .includeSubdomains)
        XCTAssertEqual(saved.domainRules[0].browser, safari.reference)
        XCTAssertEqual(saved.domainRules[0].source, .airlock)
        XCTAssertEqual(
            try repository.loadConfigurationHistory().entries.count,
            1
        )
        XCTAssertFalse(try persistedText().contains("/private"))
        XCTAssertFalse(try persistedText().contains("utm_source"))
    }

    func testProfileDeletionThroughStoreRepairsRulesAndActiveSelection() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            )
        )
        let store = makeStore()
        await store.activate()
        let profile = try XCTUnwrap(store.createProfile(named: "Work"))
        XCTAssertTrue(store.selectProfile(profile.id))
        let rule = store.createRule(
            domain: "example.com",
            browser: safari.reference,
            profileID: profile.id
        )
        XCTAssertNotNil(rule)

        XCTAssertTrue(store.deleteProfile(profile.id))

        XCTAssertNil(store.routingConfiguration.activeProfileID)
        XCTAssertTrue(store.routingConfiguration.profiles.isEmpty)
        XCTAssertTrue(store.routingConfiguration.domainRules.isEmpty)
        XCTAssertEqual(
            try repository.loadConfigurationHistory().entries.count,
            4
        )
    }

    func testUnmatchedIncomingURLStillOpensFallbackImmediately() async throws {
        try repository.saveConfiguration(
            RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            )
        )
        let store = makeStore()
        await store.activate()
        let url = try XCTUnwrap(URL(string: "https://unmatched.example/path"))

        let disposition = await store.routeIncomingURL(url)

        XCTAssertEqual(disposition, .consumed)
        XCTAssertEqual(
            launcher.calls,
            [.init(url: url, browser: chrome.reference)]
        )
        XCTAssertTrue(store.airlockResult.items.isEmpty)
    }

    private func makeStore() -> BrowserStore {
        let handler = FakeSystemBrowserHandler(
            handlers: .same(
                HandlerApplication(
                    browser: rillvia.reference,
                    applicationURL: rillvia.appURL
                )
            ),
            applications: [
                rillvia.reference: rillvia.appURL,
                chrome.reference: chrome.appURL,
                safari.reference: safari.appURL,
            ]
        )
        return BrowserStore(
            environment: AppEnvironment(
                browserCatalog: FakeBrowserCatalog(
                    browsers: [chrome, safari]
                ),
                systemBrowserHandler: handler,
                stateRepository: repository,
                urlLauncher: launcher
            )
        )
    }

    private func persistedText() throws -> String {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return ""
        }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}
