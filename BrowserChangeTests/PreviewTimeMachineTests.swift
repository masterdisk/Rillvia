import Foundation
import XCTest
@testable import BrowserChange

final class PreviewTimeMachineTests: XCTestCase {
    private let browserChange = BrowserReference(
        bundleIdentifier: "com.browserchange.BrowserChange"
    )
    private let safari = InstalledBrowser(
        id: "com.apple.Safari",
        name: "Safari",
        version: "26",
        appURL: URL(fileURLWithPath: "/Applications/Safari.app")
    )
    private let chrome = InstalledBrowser(
        id: "com.google.Chrome",
        name: "Google Chrome",
        version: "140",
        appURL: URL(
            fileURLWithPath: "/Applications/Google Chrome.app"
        )
    )
    private let missingFirefox = BrowserReference(
        bundleIdentifier: "org.mozilla.firefox"
    )

    func testTimelineIsNewestFirstBoundedAndDescribesConfigurationChanges() {
        let work = RoutingProfile(name: "Work")
        let first = RoutingConfiguration(
            fallbackBrowser: chrome.reference
        )
        let second = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome.reference,
            profiles: [work],
            activeProfileID: work.id
        )
        let third = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari.reference,
            domainRules: [
                DomainRule(
                    domain: "example.com",
                    browser: safari.reference
                ),
            ],
            profiles: [work],
            activeProfileID: work.id
        )
        let entries = [
            historyEntry(index: 1, configuration: first),
            historyEntry(index: 2, configuration: second),
            historyEntry(index: 3, configuration: third),
        ] + (4...55).map {
            historyEntry(
                index: $0,
                configuration: RoutingConfiguration(
                    mode: .smart,
                    fallbackBrowser: safari.reference,
                    domainRules: Array(
                        repeating: DomainRule(
                            domain: "rule-\($0).example",
                            browser: safari.reference
                        ),
                        count: $0 - 2
                    ),
                    profiles: [work],
                    activeProfileID: work.id
                )
            )
        }

        let model = PreviewTimeMachineModel.make(
            history: ConfigurationHistory(entries: entries),
            installedBrowsers: [safari, chrome],
            limit: 50
        )

        XCTAssertEqual(model.snapshots.count, 50)
        XCTAssertEqual(
            model.snapshots.first?.recordedAt,
            Date(timeIntervalSince1970: 55)
        )
        XCTAssertEqual(
            model.snapshots.last?.recordedAt,
            Date(timeIntervalSince1970: 6)
        )
        XCTAssertEqual(
            model.snapshots.first?.changes,
            ["Added 1 domain rule."]
        )

        let focused = PreviewTimeMachineModel.make(
            history: ConfigurationHistory(
                entries: Array(entries.prefix(3))
            ),
            installedBrowsers: [safari, chrome]
        )
        XCTAssertEqual(
            focused.snapshots[0].changes,
            [
                "Fallback changed from Google Chrome to Safari.",
                "Added 1 domain rule.",
            ]
        )
        XCTAssertEqual(
            focused.snapshots[1].changes,
            [
                "Turned Smart Routing on.",
                "Selected the Work profile.",
            ]
        )
    }

    func testEvaluationUsesHistoricalRulesAndCurrentAvailability() throws {
        let historicalRule = DomainRule(
            domain: "example.com",
            browser: missingFirefox
        )
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari.reference,
            domainRules: [historicalRule]
        )
        let entry = historyEntry(
            index: 1,
            configuration: configuration
        )
        let model = PreviewTimeMachineModel.make(
            history: ConfigurationHistory(entries: [entry]),
            installedBrowsers: [safari]
        )

        let result = model.evaluate(
            "https://example.com/private?secret=value",
            snapshotID: entry.id,
            browserChange: browserChange,
            installedBrowsers: [safari]
        )

        XCTAssertEqual(
            result,
            HistoricalRoutingEvaluation(
                target: safari.reference,
                targetName: "Safari",
                reason: "Configured external fallback"
            )
        )
        XCTAssertEqual(
            model.snapshots.first?.configuration,
            configuration,
            "Previewing must not mutate historical configuration."
        )
    }

    func testEvaluationUsesSnapshotTimeForHistoricalLease() {
        let entry = historyEntry(
            index: 150,
            configuration: RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                browserLease: BrowserLease(
                    browser: safari.reference,
                    startedAt: Date(timeIntervalSince1970: 100),
                    expiresAt: Date(timeIntervalSince1970: 200)
                )
            )
        )
        let model = PreviewTimeMachineModel.make(
            history: ConfigurationHistory(entries: [entry]),
            installedBrowsers: [safari, chrome]
        )

        let result = model.evaluate(
            "https://example.com",
            snapshotID: entry.id,
            browserChange: browserChange,
            installedBrowsers: [safari, chrome]
        )

        XCTAssertEqual(
            result,
            HistoricalRoutingEvaluation(
                target: safari.reference,
                targetName: "Safari",
                reason: "Active browser lease"
            )
        )
    }

    func testEvaluationRejectsNonWebInputWithoutRetainingIt() {
        let entry = historyEntry(
            index: 1,
            configuration: RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: safari.reference
            )
        )
        let model = PreviewTimeMachineModel.make(
            history: ConfigurationHistory(entries: [entry]),
            installedBrowsers: [safari]
        )

        let result = model.evaluate(
            "file:///private/clipboard-secret.txt",
            snapshotID: entry.id,
            browserChange: browserChange,
            installedBrowsers: [safari]
        )

        XCTAssertNil(result.target)
        XCTAssertEqual(
            result.reason,
            "Enter an HTTP or HTTPS URL."
        )
        XCTAssertFalse(
            String(reflecting: model).contains("clipboard-secret")
        )
    }

    private func historyEntry(
        index: Int,
        configuration: RoutingConfiguration
    ) -> ConfigurationHistoryEntry {
        ConfigurationHistoryEntry(
            id: UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    index
                )
            )!,
            recordedAt: Date(timeIntervalSince1970: Double(index)),
            configuration: configuration
        )
    }
}
