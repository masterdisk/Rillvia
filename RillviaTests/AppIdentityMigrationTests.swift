import Foundation
import XCTest
@testable import Rillvia

final class AppIdentityMigrationTests: XCTestCase {
    private var applicationSupport: URL!
    private var legacyDirectory: URL!
    private let appURL = URL(fileURLWithPath: "/Applications/Rillvia.app")
    private let safari = BrowserReference(bundleIdentifier: "com.apple.Safari")
    private let legacy = BrowserReference(bundleIdentifier: AppIdentityMigration.legacyBundleIdentifier)
    private let current = BrowserReference(bundleIdentifier: AppIdentity.bundleIdentifier)

    override func setUpWithError() throws {
        applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("RillviaIdentityTests-\(UUID().uuidString)", isDirectory: true)
        legacyDirectory = applicationSupport.appendingPathComponent(AppIdentityMigration.legacySupportDirectoryName, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: applicationSupport)
    }

    func testImportsRulesProfilesLeaseAndHistoryWithoutChangingTheOriginal() throws {
        let profile = RoutingProfile(name: "Work")
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari,
            domainRules: [DomainRule(domain: "example.com", browser: safari, profileID: profile.id)],
            profiles: [profile],
            activeProfileID: profile.id,
            browserLease: BrowserLease(browser: safari, startedAt: .now, expiresAt: nil),
            allowAutomationLeases: true
        )
        let history = ConfigurationHistory(entries: [
            ConfigurationHistoryEntry(id: UUID(), recordedAt: .now, configuration: configuration),
        ])
        let old = StateRepository(baseDirectory: legacyDirectory)
        try old.saveConfiguration(configuration)
        try old.saveConfigurationHistory(history)
        let configurationBytes = try Data(contentsOf: legacyDirectory.appendingPathComponent("configuration.json"))
        let historyBytes = try Data(contentsOf: legacyDirectory.appendingPathComponent("configuration-history.json"))

        let repository = StateRepository(applicationSupport: applicationSupport)

        XCTAssertEqual(repository.baseDirectory.lastPathComponent, "Rillvia")
        XCTAssertEqual(try repository.loadConfiguration(), configuration)
        XCTAssertEqual(try repository.loadConfigurationHistory(), history)
        XCTAssertEqual(try Data(contentsOf: legacyDirectory.appendingPathComponent("configuration.json")), configurationBytes)
        XCTAssertEqual(try Data(contentsOf: legacyDirectory.appendingPathComponent("configuration-history.json")), historyBytes)
    }

    func testRewritesSelfReferencesAndAppPathsInPendingOperationsAndUndo() throws {
        let oldSelf = HandlerApplication(browser: legacy, applicationURL: applicationSupport.appendingPathComponent("old.app"))
        let external = HandlerApplication(browser: safari, applicationURL: URL(fileURLWithPath: "/Applications/Safari.app"))
        let original = RoutingConfiguration(mode: .smart, fallbackBrowser: legacy)
        let undo = HandlerUndoReceipt(operationID: UUID(), issuedAt: .now, precondition: .same(oldSelf), restore: .same(external))
        let journal = HandlerOperationJournal(
            pendingOperation: PendingHandlerOperation(
                id: undo.operationID,
                startedAt: .now,
                kind: .smartActivation,
                desiredHandlers: .same(oldSelf),
                undoReceipt: undo,
                completedSchemes: [.http],
                configurationBefore: original,
                configurationOnSuccess: original
            ),
            undoReceipt: undo
        )
        let old = StateRepository(baseDirectory: legacyDirectory)
        try old.saveConfiguration(original)
        try old.saveHandlerJournal(journal)
        try old.saveConfigurationHistory(ConfigurationHistory(entries: [
            ConfigurationHistoryEntry(id: UUID(), recordedAt: .now, configuration: original),
        ]))
        let journalBytes = try Data(contentsOf: legacyDirectory.appendingPathComponent("handler-journal.json"))

        let destination = try AppIdentityMigration.migrateState(in: applicationSupport, appURL: appURL)
        let repository = StateRepository(baseDirectory: destination)
        let updated = try repository.loadHandlerJournal()
        let newSelf = HandlerApplication(browser: current, applicationURL: appURL)

        XCTAssertEqual(updated.undoReceipt?.precondition, .same(newSelf))
        XCTAssertEqual(updated.undoReceipt?.restore, .same(external))
        XCTAssertEqual(updated.pendingOperation?.desiredHandlers, .same(newSelf))
        XCTAssertEqual(updated.pendingOperation?.completedSchemes, [.http])
        XCTAssertEqual(updated.pendingOperation?.configurationBefore?.fallbackBrowser, current)
        XCTAssertEqual(updated.pendingOperation?.configurationOnSuccess?.fallbackBrowser, current)
        XCTAssertEqual(try repository.loadConfiguration().fallbackBrowser, current)
        XCTAssertEqual(try repository.loadConfigurationHistory().entries.first?.configuration.fallbackBrowser, current)
        XCTAssertEqual(try Data(contentsOf: legacyDirectory.appendingPathComponent("handler-journal.json")), journalBytes)
    }

    func testExistingRillviaStateWinsAndIsNotMergedOrOverwritten() throws {
        try StateRepository(baseDirectory: legacyDirectory).saveConfiguration(RoutingConfiguration(mode: .smart))
        let destination = applicationSupport.appendingPathComponent("Rillvia", isDirectory: true)
        let existing = StateRepository(baseDirectory: destination)
        let configuration = RoutingConfiguration(fallbackBrowser: safari)
        try existing.saveConfiguration(configuration)
        let bytes = try Data(contentsOf: destination.appendingPathComponent("configuration.json"))

        XCTAssertEqual(try AppIdentityMigration.migrateState(in: applicationSupport, appURL: appURL), destination)
        XCTAssertEqual(try existing.loadConfiguration(), configuration)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("configuration.json")), bytes)
    }

    func testMissingLegacyStateDoesNotCreateAStorageDirectory() throws {
        let repository = StateRepository(applicationSupport: applicationSupport)

        XCTAssertEqual(try repository.loadConfiguration(), .fresh)
        XCTAssertFalse(FileManager.default.fileExists(atPath: applicationSupport.path))
    }

    func testFutureSchemasAndCorruptFilesAreCopiedUnchanged() throws {
        let old = StateRepository(baseDirectory: legacyDirectory)
        try old.saveConfiguration(RoutingConfiguration(fallbackBrowser: legacy))
        let file = legacyDirectory.appendingPathComponent("configuration.json")
        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        future["schemaVersion"] = RoutingConfiguration.currentSchemaVersion + 1
        let futureBytes = try JSONSerialization.data(withJSONObject: future)
        try futureBytes.write(to: file)
        let corruptBytes = Data("unfinished journal".utf8)
        try corruptBytes.write(to: legacyDirectory.appendingPathComponent("handler-journal.json"))

        let destination = try AppIdentityMigration.migrateState(in: applicationSupport, appURL: appURL)
        let repository = StateRepository(baseDirectory: destination)

        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("configuration.json")), futureBytes)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("handler-journal.json")), corruptBytes)
        XCTAssertThrowsError(try repository.loadConfiguration())
        XCTAssertThrowsError(try repository.saveConfiguration(.fresh))
        XCTAssertEqual(try Data(contentsOf: file), futureBytes)
        XCTAssertEqual(try Data(contentsOf: legacyDirectory.appendingPathComponent("handler-journal.json")), corruptBytes)
    }

    func testUnknownFilesAndFieldsSurviveImport() throws {
        let old = StateRepository(baseDirectory: legacyDirectory)
        try old.saveConfiguration(RoutingConfiguration(fallbackBrowser: legacy))
        let file = legacyDirectory.appendingPathComponent("configuration.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["additionalNote"] = "keep this field"
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let backup = Data("previous saved bytes".utf8)
        try backup.write(to: legacyDirectory.appendingPathComponent("configuration.backup"))

        let destination = try AppIdentityMigration.migrateState(in: applicationSupport, appURL: appURL)
        let updated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: destination.appendingPathComponent("configuration.json"))) as? [String: Any])

        XCTAssertEqual(updated["additionalNote"] as? String, "keep this field")
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("configuration.backup")), backup)
    }

    func testFailedCopyLeavesNoPartialDestinationAndBlocksRepositoryWrites() throws {
        let old = StateRepository(baseDirectory: legacyDirectory)
        try old.saveConfiguration(RoutingConfiguration(mode: .smart, fallbackBrowser: safari))
        let bytes = try Data(contentsOf: legacyDirectory.appendingPathComponent("configuration.json"))
        let repository = StateRepository(applicationSupport: applicationSupport, fileManager: InterruptedImportFileManager())

        XCTAssertThrowsError(try repository.loadConfiguration()) { error in
            XCTAssertEqual(error as? StateRepositoryError, .identityImportFailed)
        }
        XCTAssertThrowsError(try repository.inspectConfigurationHistory())
        XCTAssertThrowsError(try repository.saveConfiguration(.fresh))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: applicationSupport.path), [legacyDirectory.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: legacyDirectory.appendingPathComponent("configuration.json")), bytes)
    }

    @MainActor
    func testPreferencesImportOncePreservesCurrentValuesAndShortcutBytes() throws {
        let suite = "RillviaIdentityPreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let oldSuite = "\(suite)-previous"
        let oldDefaults = try XCTUnwrap(UserDefaults(suiteName: oldSuite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            oldDefaults.removePersistentDomain(forName: oldSuite)
        }
        let binding = ShortcutBinding(
            chord: ShortcutChord(keyCode: 8, modifiers: [.control, .option, .shift], key: "C"),
            scope: .rillvia,
            action: ShortcutAction(kind: .useBrowser, browserID: safari.id)
        )
        XCTAssertNil(KeyboardShortcutStore(defaults: oldDefaults).save(binding))
        let shortcutBytes = try XCTUnwrap(oldDefaults.data(forKey: KeyboardShortcutStore.preferencesKey))
        defaults.set("dark", forKey: "appearance")

        AppIdentityMigration.migratePreferences(to: defaults, legacyValues: [
            "appearance": "light", "hasSeenIntro": true, KeyboardShortcutStore.preferencesKey: shortcutBytes,
        ])
        AppIdentityMigration.migratePreferences(to: defaults, legacyValues: [
            "hasSeenIntro": false, "laterLegacyValue": "must not be reimported",
        ])

        XCTAssertEqual(defaults.string(forKey: "appearance"), "dark")
        XCTAssertTrue(defaults.bool(forKey: "hasSeenIntro"))
        XCTAssertEqual(defaults.data(forKey: KeyboardShortcutStore.preferencesKey), shortcutBytes)
        XCTAssertEqual(KeyboardShortcutStore(defaults: defaults).bindings, [binding])
        XCTAssertNil(defaults.object(forKey: "laterLegacyValue"))
    }

    func testLegacyIdentityCannotBecomeAnExternalRoutingTarget() throws {
        let engine = RoutingEngine(rillvia: current)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari,
            domainRules: [DomainRule(domain: "example.com", browser: legacy)]
        )

        XCTAssertEqual(try engine.decision(for: url, configuration: configuration).target, safari)
        XCTAssertThrowsError(try engine.decision(for: url, configuration: configuration, explicitTarget: legacy)) { error in
            XCTAssertEqual(error as? RoutingIssue, .explicitTargetUnavailable(self.legacy))
        }
        XCTAssertThrowsError(try engine.decision(for: url, configuration: RoutingConfiguration(mode: .smart, fallbackBrowser: legacy))) { error in
            XCTAssertEqual(error as? RoutingIssue, .selfTarget)
        }
    }
}

private final class InterruptedImportFileManager: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try FileManager.default.createDirectory(at: dstURL, withIntermediateDirectories: true)
        throw CocoaError(.fileWriteUnknown)
    }
}
