import Foundation
import XCTest
@testable import Rillvia

final class PreviewTimeMachineTests: XCTestCase {
    private let rillvia = BrowserReference(
        bundleIdentifier: "com.rillvia.app"
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

    func testTimelineUsesRepositoryTrimmedHistoryAndDescribesChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewTimeMachineTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StateRepository(baseDirectory: directory)

        for index in 1...55 {
            let configuration = RoutingConfiguration(
                fallbackBrowser: safari.reference,
                domainRules: Array(
                    repeating: DomainRule(
                        domain: "rule-\(index).example",
                        browser: safari.reference
                    ),
                    count: index
                )
            )
            try repository.appendConfigurationSnapshot(
                configuration,
                recordedAt: Date(timeIntervalSince1970: Double(index)),
                historyLimit: 50
            )
        }

        let persistedHistory = try repository.inspectConfigurationHistory()
        XCTAssertEqual(persistedHistory.entries.count, 50)
        XCTAssertEqual(
            persistedHistory.entries.first?.recordedAt,
            Date(timeIntervalSince1970: 6)
        )

        let model = PreviewTimeMachineModel.make(
            history: persistedHistory,
            installedBrowsers: [safari, chrome]
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
        XCTAssertEqual(
            model.snapshots.last?.changes,
            ["Oldest retained snapshot. Earlier changes are unavailable."]
        )
        XCTAssertEqual(
            model.snapshots.dropLast().last?.changes,
            ["Added 1 domain rule."]
        )
    }

    func testTimelineDescribesConfigurationChanges() {
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
        ]

        let focused = PreviewTimeMachineModel.make(
            history: ConfigurationHistory(entries: entries),
            installedBrowsers: [safari, chrome]
        )
        XCTAssertEqual(
            focused.snapshots[0].changes,
            [
                "The browser for sites with no rule changed from Google Chrome to Safari.",
                "Added 1 domain rule.",
            ]
        )
        XCTAssertEqual(
            focused.snapshots[1].changes,
            [
                "Started sending links through Rillvia.",
                "Added the Work rule set.",
                "Selected the Work rule set.",
            ]
        )
        XCTAssertEqual(
            focused.snapshots[2].changes,
            ["Oldest retained snapshot. Earlier changes are unavailable."]
        )
    }

    func testTimelineDescribesProfileOnlyChanges() {
        let profileID = UUID()
        let first = RoutingConfiguration()
        var profile = RoutingProfile(
            id: profileID,
            name: "Work",
            browser: chrome.reference
        )
        let second = RoutingConfiguration(profiles: [profile])

        profile.name = "Client"
        profile.revision = 2
        var third = second
        third.profiles = [profile]

        profile.isEnabled = false
        profile.revision = 3
        var fourth = third
        fourth.profiles = [profile]

        profile.isEnabled = true
        profile.revision = 4
        var fifth = fourth
        fifth.profiles = [profile]

        profile.browser = safari.reference
        profile.revision = 5
        var sixth = fifth
        sixth.profiles = [profile]

        profile.source = .airlock
        profile.revision = 6
        var seventh = sixth
        seventh.profiles = [profile]

        var eighth = seventh
        eighth.profiles = []

        let configurations = [
            first,
            second,
            third,
            fourth,
            fifth,
            sixth,
            seventh,
            eighth,
        ]
        let snapshots = Array(PreviewTimeMachineModel.make(
            history: ConfigurationHistory(
                entries: configurations.enumerated().map {
                    historyEntry(
                        index: $0.offset + 1,
                        configuration: $0.element
                    )
                }
            ),
            installedBrowsers: [safari, chrome]
        ).snapshots.reversed())

        XCTAssertEqual(snapshots[1].changes, ["Added the Work rule set."])
        XCTAssertEqual(
            snapshots[2].changes,
            ["Renamed the Work rule set to Client."]
        )
        XCTAssertEqual(
            snapshots[3].changes,
            ["Disabled the Client rule set."]
        )
        XCTAssertEqual(
            snapshots[4].changes,
            ["Enabled the Client rule set."]
        )
        XCTAssertEqual(
            snapshots[5].changes,
            ["Changed the browser for the Client rule set from Google Chrome to Safari."]
        )
        XCTAssertEqual(
            snapshots[6].changes,
            ["Updated the Client rule set."]
        )
        XCTAssertEqual(
            snapshots[7].changes,
            ["Removed the Client rule set."]
        )
        XCTAssertFalse(
            snapshots.dropFirst().contains {
                $0.changes == ["No configuration changes."]
            }
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
            rillvia: rillvia,
            installedBrowsers: [safari]
        )

        XCTAssertEqual(
            result,
            HistoricalRoutingEvaluation(
                target: safari.reference,
                targetName: "Safari",
                reason: "Your usual browser"
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
            rillvia: rillvia,
            installedBrowsers: [safari, chrome]
        )

        XCTAssertEqual(
            result,
            HistoricalRoutingEvaluation(
                target: safari.reference,
                targetName: "Safari",
                reason: "Temporary browser"
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
            rillvia: rillvia,
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
