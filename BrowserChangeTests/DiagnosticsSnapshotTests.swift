import AppKit
import XCTest
@testable import BrowserChange

@MainActor
final class DiagnosticsSnapshotTests: XCTestCase {
    private let browserChange = BrowserReference(
        bundleIdentifier: "com.browserchange.BrowserChange"
    )
    private let safari = InstalledBrowser(
        id: "com.apple.Safari",
        name: "Safari",
        version: "26.0",
        appURL: URL(
            fileURLWithPath: "/Applications/private/Safari.app"
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

    func testSnapshotContainsUsefulHealthFactsWithoutSensitiveValues() {
        let profile = RoutingProfile(name: "Work")
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.reference,
            domainRules: [
                DomainRule(
                    domain: "secret.example",
                    browser: safari.reference,
                    profileID: profile.id
                ),
                DomainRule(
                    domain: "disabled.example",
                    browser: chrome.reference,
                    isEnabled: false
                ),
            ],
            profiles: [profile],
            activeProfileID: profile.id,
            browserLease: BrowserLease(
                browser: safari.reference,
                startedAt: Date(timeIntervalSince1970: 1_900_000_000),
                expiresAt: nil
            )
        )
        let browserChangeApplication = HandlerApplication(
            browser: browserChange,
            applicationURL: URL(
                fileURLWithPath: "/Applications/BrowserChange.app"
            )
        )
        let safariApplication = HandlerApplication(
            browser: safari.reference,
            applicationURL: safari.appURL
        )
        let operationID = UUID()
        let pending = PendingHandlerOperation(
            id: operationID,
            startedAt: Date(timeIntervalSince1970: 1_900_000_000),
            kind: .smartActivation,
            desiredHandlers: .same(browserChangeApplication),
            undoReceipt: HandlerUndoReceipt(
                operationID: operationID,
                issuedAt: Date(timeIntervalSince1970: 1_900_000_000),
                precondition: .same(browserChangeApplication),
                restore: .same(safariApplication)
            ),
            completedSchemes: [.https],
            inFlightScheme: .http
        )

        let snapshot = DiagnosticsSnapshot.make(
            appName: "BrowserChange",
            appVersion: "1.0",
            buildVersion: "7",
            browserChange: browserChange,
            handlers: HTTPHandlerSnapshot(
                http: safariApplication,
                https: browserChangeApplication
            ),
            routingState: .smartSuspended(chrome.reference),
            configuration: configuration,
            journal: HandlerOperationJournal(
                pendingOperation: pending
            ),
            canUndo: false,
            installedBrowsers: [safari, chrome],
            now: Date(timeIntervalSince1970: 1_900_000_100)
        )
        let text = snapshot.visibleText

        XCTAssertTrue(text.contains("BrowserChange 1.0 (7)"))
        XCTAssertTrue(text.contains("Configuration schema: 4"))
        XCTAssertTrue(text.contains("Handler journal schema: 4"))
        XCTAssertTrue(text.contains("History schema: 1"))
        XCTAssertTrue(text.contains("HTTP: com.apple.Safari — external"))
        XCTAssertTrue(
            text.contains(
                "HTTPS: com.browserchange.BrowserChange — BrowserChange"
            )
        )
        XCTAssertTrue(text.contains("Ownership health: split"))
        XCTAssertTrue(text.contains("Routing mode: Smart"))
        XCTAssertTrue(text.contains("Routing state: Suspended"))
        XCTAssertTrue(
            text.contains(
                "External fallback: Google Chrome (com.google.Chrome)"
            )
        )
        XCTAssertTrue(text.contains("Active profile: Work"))
        XCTAssertTrue(text.contains("Rules: 1 enabled, 2 total"))
        XCTAssertTrue(
            text.contains(
                "Temporary browser: Safari (com.apple.Safari), until you stop"
            )
        )
        XCTAssertTrue(text.contains("Pending operation: Smart activation"))
        XCTAssertTrue(text.contains("Progress: 1 of 2 handlers complete"))
        XCTAssertTrue(text.contains("In flight: HTTP"))
        XCTAssertTrue(text.contains("Undo available: No"))
        XCTAssertTrue(
            text.contains("Safari 26.0 — com.apple.Safari")
        )
        XCTAssertTrue(
            text.contains("Google Chrome 140 — com.google.Chrome")
        )

        for secret in [
            "secret.example",
            "disabled.example",
            "/Applications/private",
            "/private/path",
            "secret=value",
            "clipboard-secret",
        ] {
            XCTAssertFalse(
                text.contains(secret),
                "Diagnostics leaked \(secret)"
            )
        }
    }

    func testCopyWritesExactlyTheVisibleRedactedSnapshot() throws {
        let snapshot = DiagnosticsSnapshot.make(
            appName: "BrowserChange",
            appVersion: "1.0",
            buildVersion: "1",
            browserChange: browserChange,
            handlers: .missing,
            routingState: .direct,
            configuration: .fresh,
            journal: .fresh,
            canUndo: false,
            installedBrowsers: [safari],
            now: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name(
                "DiagnosticsSnapshotTests-\(UUID().uuidString)"
            )
        )
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(snapshot.copy(to: pasteboard))
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            snapshot.visibleText
        )
    }

    func testSnapshotReportsVersionsLoadedFromPersistedState() {
        let snapshot = DiagnosticsSnapshot.make(
            appName: "BrowserChange",
            appVersion: "1.0",
            buildVersion: "1",
            browserChange: browserChange,
            handlers: .missing,
            routingState: .direct,
            configuration: RoutingConfiguration(
                schemaVersion: 2
            ),
            journal: HandlerOperationJournal(
                schemaVersion: 3
            ),
            historySchemaVersion: 1,
            canUndo: false,
            installedBrowsers: [],
            now: Date(timeIntervalSince1970: 1_900_000_000)
        )

        XCTAssertTrue(
            snapshot.visibleText.contains(
                "Configuration schema: 2"
            )
        )
        XCTAssertTrue(
            snapshot.visibleText.contains(
                "Handler journal schema: 3"
            )
        )
        XCTAssertTrue(
            snapshot.visibleText.contains("History schema: 1")
        )
    }
}
