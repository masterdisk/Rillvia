import Foundation
import XCTest
@testable import BrowserChange

final class RoutingConfigurationPersistenceTests: XCTestCase {
    private let browserChange = BrowserReference(
        bundleIdentifier: "com.browserchange.BrowserChange"
    )
    private let safari = BrowserReference(bundleIdentifier: "com.apple.Safari")

    func testTask3SchemaMigratesWithoutCreatingSyntheticRules() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let task3JSON = """
        {
          "schemaVersion": 1,
          "mode": "smart",
          "fallbackBrowser": {"bundleIdentifier": "com.apple.Safari"},
          "domainRules": [],
          "profiles": [],
          "leases": []
        }
        """
        try Data(task3JSON.utf8).write(
            to: directory.appendingPathComponent("configuration.json")
        )

        let migrated = try StateRepository(
            baseDirectory: directory
        ).loadConfiguration()

        XCTAssertEqual(
            migrated.schemaVersion,
            RoutingConfiguration.currentSchemaVersion
        )
        XCTAssertEqual(migrated.fallbackBrowser, safari)
        XCTAssertTrue(migrated.domainRules.isEmpty)
        XCTAssertTrue(migrated.profiles.isEmpty)
        XCTAssertNil(migrated.activeProfileID)
    }

    func testConfigurationSnapshotsAreBoundedAndContainConfigurationOnly() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = StateRepository(baseDirectory: directory)

        for revision in 1...5 {
            let configuration = RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: safari,
                domainRules: [
                    DomainRule(
                        revision: revision,
                        domain: "example.com",
                        browser: safari
                    ),
                ]
            )
            try repository.saveConfigurationSnapshot(
                configuration,
                recordedAt: Date(timeIntervalSince1970: Double(revision)),
                historyLimit: 3
            )
        }

        let history = try repository.loadConfigurationHistory()
        XCTAssertEqual(history.entries.count, 3)
        XCTAssertEqual(
            history.entries.map {
                $0.configuration.domainRules[0].revision
            },
            [3, 4, 5]
        )
        let persisted = try String(
            contentsOf: directory.appendingPathComponent(
                "configuration-history.json"
            ),
            encoding: .utf8
        )
        XCTAssertFalse(persisted.contains("/private/path"))
        XCTAssertFalse(persisted.contains("secret="))
    }

    func testRuleAndProfileEditsNormalizeAndRepairReferences() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let editor = RoutingConfigurationEditor(
            browserChange: browserChange,
            now: { now }
        )
        var configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari
        )

        let profile = try editor.createProfile(
            named: "Work",
            in: &configuration
        )
        try editor.selectProfile(profile.id, in: &configuration)
        let rule = try editor.createRule(
            domain: "BÜCHER.Example.",
            scope: .includeSubdomains,
            browser: safari,
            profileID: profile.id,
            source: .airlock,
            in: &configuration
        )

        XCTAssertEqual(rule.domain, "xn--bcher-kva.example")
        XCTAssertEqual(rule.source, .airlock)
        XCTAssertEqual(rule.createdAt, now)
        XCTAssertEqual(configuration.activeProfileID, profile.id)

        try editor.setRuleEnabled(
            rule.id,
            isEnabled: false,
            in: &configuration
        )
        XCTAssertEqual(configuration.domainRules[0].revision, 2)
        XCTAssertFalse(configuration.domainRules[0].isEnabled)

        try editor.renameProfile(
            profile.id,
            to: "Client",
            in: &configuration
        )
        XCTAssertEqual(configuration.profiles[0].name, "Client")
        XCTAssertEqual(configuration.profiles[0].revision, 2)

        try editor.deleteProfile(profile.id, in: &configuration)
        XCTAssertNil(configuration.activeProfileID)
        XCTAssertTrue(configuration.profiles.isEmpty)
        XCTAssertTrue(
            configuration.domainRules.isEmpty,
            "Profile rules must not silently become global."
        )
    }

    func testEditorRejectsBrowserChangeAsRuleTarget() throws {
        let editor = RoutingConfigurationEditor(
            browserChange: browserChange
        )
        var configuration = RoutingConfiguration.fresh

        XCTAssertThrowsError(
            try editor.createRule(
                domain: "example.com",
                browser: browserChange,
                in: &configuration
            )
        ) {
            XCTAssertEqual(
                $0 as? RoutingConfigurationIssue,
                .selfTarget
            )
        }
        XCTAssertTrue(configuration.domainRules.isEmpty)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "RoutingConfigurationPersistenceTests-\(UUID().uuidString)"
        )
    }
}
