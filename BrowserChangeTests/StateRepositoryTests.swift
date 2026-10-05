import Foundation
import XCTest
@testable import BrowserChange

final class StateRepositoryTests: XCTestCase {
    private var directory: URL!
    private var repository: StateRepository!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StateRepositoryTests-\(UUID().uuidString)")
        repository = StateRepository(baseDirectory: directory)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testMissingFilesReturnFreshDefaultsWithoutCreatingFiles() throws {
        XCTAssertEqual(try repository.loadConfiguration(), .fresh)
        XCTAssertEqual(try repository.loadHandlerJournal(), .fresh)
        XCTAssertEqual(try repository.loadConfigurationHistory(), .fresh)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testRoundTripsEachVersionedStateFile() throws {
        let safari = BrowserReference(bundleIdentifier: "com.apple.Safari")
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari,
            domainRules: [
                DomainRule(
                    domain: "example.com",
                    browser: safari
                ),
            ]
        )
        let handlers = HTTPHandlerSnapshot.same(
            HandlerApplication(
                browser: safari,
                applicationURL: URL(fileURLWithPath: "/Applications/Safari.app")
            )
        )
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let journal = HandlerOperationJournal(
            pendingOperation: PendingHandlerOperation(
                id: operationID,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                desiredHandlers: handlers,
                undoReceipt: HandlerUndoReceipt(
                    operationID: operationID,
                    issuedAt: Date(timeIntervalSince1970: 1_700_000_001),
                    precondition: handlers,
                    restore: .missing
                )
            )
        )
        let history = ConfigurationHistory(
            entries: [
                ConfigurationHistoryEntry(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                    recordedAt: Date(timeIntervalSince1970: 1_700_000_002),
                    configuration: configuration
                ),
            ]
        )

        try repository.saveConfiguration(configuration)
        try repository.saveHandlerJournal(journal)
        try repository.saveConfigurationHistory(history)

        XCTAssertEqual(try repository.loadConfiguration(), configuration)
        XCTAssertEqual(try repository.loadHandlerJournal(), journal)
        XCTAssertEqual(try repository.loadConfigurationHistory(), history)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("configuration.json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("handler-journal.json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("configuration-history.json").path
        ))
    }

    func testCorruptFileIsQuarantinedAndReturnsSafeDefault() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let configurationURL = directory.appendingPathComponent("configuration.json")
        try Data("not json".utf8).write(to: configurationURL)

        XCTAssertEqual(try repository.loadConfiguration(), .fresh)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configurationURL.path))

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(
            names.filter {
                $0.hasPrefix("configuration.corrupt-") && $0.hasSuffix(".json")
            }.count,
            1
        )
    }

    func testFutureSchemaIsNeitherQuarantinedNorOverwritten() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let configurationURL = directory.appendingPathComponent("configuration.json")
        let original = Data(#"{"schemaVersion":999,"futureValue":"keep me"}"#.utf8)
        try original.write(to: configurationURL)

        XCTAssertThrowsError(try repository.loadConfiguration()) { error in
            XCTAssertEqual(
                error as? StateRepositoryError,
                .unsupportedSchema(
                    fileName: "configuration.json",
                    found: 999,
                    supported: RoutingConfiguration.currentSchemaVersion
                )
            )
        }
        XCTAssertThrowsError(try repository.saveConfiguration(.fresh))
        XCTAssertEqual(try Data(contentsOf: configurationURL), original)

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(names.contains { $0.contains(".corrupt-") })
    }

    func testAtomicReplacementLeavesNoTemporaryFileBehind() throws {
        try repository.saveConfiguration(.fresh)
        var changed = RoutingConfiguration.fresh
        changed.mode = .smart
        try repository.saveConfiguration(changed)

        XCTAssertEqual(try repository.loadConfiguration(), changed)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(names.contains { $0.hasSuffix(".tmp") })
    }
}
