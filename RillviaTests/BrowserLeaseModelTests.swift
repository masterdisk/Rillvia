import Foundation
import XCTest
@testable import Rillvia

final class BrowserLeaseModelTests: XCTestCase {
    private let safari = BrowserReference(
        bundleIdentifier: "com.apple.Safari"
    )

    func testBrowserLeaseRoundTripsWithoutBrowsingData() throws {
        let lease = BrowserLease(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000501"
            )!,
            revision: 3,
            browser: safari,
            startedAt: Date(timeIntervalSince1970: 1_900_000_000),
            expiresAt: nil
        )

        let data = try JSONEncoder().encode(lease)
        let decoded = try JSONDecoder().decode(
            BrowserLease.self,
            from: data
        )
        let persisted = try XCTUnwrap(
            String(data: data, encoding: .utf8)
        )

        XCTAssertEqual(decoded, lease)
        XCTAssertFalse(persisted.localizedCaseInsensitiveContains("url"))
        XCTAssertFalse(persisted.localizedCaseInsensitiveContains("domain"))
        XCTAssertFalse(persisted.localizedCaseInsensitiveContains("history"))
    }

    func testTask4PlaceholderLeasesMigrateWithoutBecomingActive() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BrowserLeaseModelTests-\(UUID().uuidString)"
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let legacy = """
        {
          "schemaVersion": 2,
          "mode": "smart",
          "fallbackBrowser": {
            "bundleIdentifier": "com.apple.Safari"
          },
          "domainRules": [],
          "profiles": [],
          "leases": [{
            "id": "00000000-0000-0000-0000-000000000502",
            "revision": 1,
            "domain": "private.example",
            "browser": {
              "bundleIdentifier": "com.google.Chrome"
            },
            "expiresAt": 900000000
          }]
        }
        """
        try Data(legacy.utf8).write(
            to: directory.appendingPathComponent("configuration.json")
        )

        let migrated = try StateRepository(
            baseDirectory: directory
        ).loadConfiguration()

        XCTAssertEqual(
            migrated.schemaVersion,
            RoutingConfiguration.currentSchemaVersion
        )
        XCTAssertNil(migrated.browserLease)
    }
}
