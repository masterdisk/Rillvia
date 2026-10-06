import AppIntents
import Foundation
import XCTest
@testable import BrowserChange

@MainActor
final class AppIntentsMetadataTests: XCTestCase {
    private let browserChange = InstalledBrowser(
        id: "com.browserchange.BrowserChange",
        name: "BrowserChange",
        version: "1",
        appURL: URL(fileURLWithPath: "/Applications/BrowserChange.app")
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

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AppIntentsMetadataTests-\(UUID().uuidString)"
            )
        repository = StateRepository(baseDirectory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testEntitiesUseStableIdentifiersAndClearDisplayRepresentations() {
        let browser = InstalledBrowserEntity(
            id: safari.id,
            name: safari.name
        )
        let profileID = UUID()
        let profile = RoutingProfileEntity(
            id: profileID,
            name: "Work"
        )

        XCTAssertEqual(browser.id, safari.id)
        XCTAssertEqual(
            String(localized: browser.displayRepresentation.title),
            "Safari"
        )
        XCTAssertEqual(
            browser.displayRepresentation.subtitle.map {
                String(localized: $0)
            },
            "Installed browser"
        )
        XCTAssertEqual(profile.id, profileID)
        XCTAssertEqual(
            String(localized: profile.displayRepresentation.title),
            "Work"
        )
        XCTAssertEqual(
            profile.displayRepresentation.subtitle.map {
                String(localized: $0)
            },
            "Enabled rule set"
        )
    }

    func testEntityQueriesResolveOnlyCurrentValidValuesThroughRegisteredDependency() async throws {
        let work = RoutingProfile(name: "Work")
        let disabled = RoutingProfile(name: "Disabled", isEnabled: false)
        try repository.saveConfiguration(
            RoutingConfiguration(profiles: [work, disabled])
        )
        let handler = FakeSystemBrowserHandler(
            handlers: .same(application(chrome)),
            applications: [
                browserChange.reference: browserChange.appURL,
                chrome.reference: chrome.appURL,
                safari.reference: safari.appURL,
            ]
        )
        let services = BrowserChangeServices(
            environment: AppEnvironment(
                browserCatalog: FakeBrowserCatalog(
                    browsers: [browserChange, chrome, safari]
                ),
                systemBrowserHandler: handler,
                stateRepository: repository,
                urlLauncher: FakeURLLauncher(),
                leaseScheduler: MetadataLeaseScheduler()
            ),
            browserChange: browserChange.reference
        )
        let manager = AppDependencyManager()
        BrowserChangeIntentDependencies.register(
            services.intentBridge,
            manager: manager
        )

        let browsers = try await InstalledBrowserEntityQuery(
            bridge: services.intentBridge
        ).entities(
            for: [
                safari.id,
                browserChange.id,
                "com.example.Missing",
            ]
        )
        let profiles = try await RoutingProfileEntityQuery(
            bridge: services.intentBridge
        ).entities(for: [work.id, disabled.id, UUID()])

        XCTAssertEqual(browsers.map(\.id), [safari.id])
        XCTAssertEqual(profiles.map(\.id), [work.id])
    }

    func testIntentsShortcutsAndLeasePresetMetadataCanBeInstantiated() {
        _ = OpenLinkIntent()
        _ = SetRoutingProfileIntent()
        _ = StartBrowserLeaseIntent()
        _ = EndBrowserLeaseIntent()
        _ = RestorePreviousBrowserIntent()

        XCTAssertTrue(OpenLinkIntent.supportedModes.contains(.background))
        XCTAssertTrue(
            StartBrowserLeaseIntent.supportedModes.contains(.background)
        )
        XCTAssertEqual(BrowserChangeAppShortcuts.appShortcuts.count, 5)
        XCTAssertEqual(
            BrowserLeasePreset.caseDisplayRepresentations.count,
            BrowserLeasePreset.allCases.count
        )
    }

    func testHostAppRegistersHTTPAndHTTPSAsAlternateViewerSchemes() throws {
        let urlTypes = try XCTUnwrap(
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleURLTypes"
            ) as? [[String: Any]]
        )
        let webType = try XCTUnwrap(
            urlTypes.first {
                Set($0["CFBundleURLSchemes"] as? [String] ?? [])
                    == Set(["http", "https"])
            }
        )

        XCTAssertEqual(
            webType["CFBundleTypeRole"] as? String,
            "Viewer"
        )
        XCTAssertEqual(
            webType["LSHandlerRank"] as? String,
            "Alternate"
        )
        XCTAssertEqual(
            webType["CFBundleURLName"] as? String,
            "com.browserchange.BrowserChange.web"
        )
    }

    private func application(
        _ browser: InstalledBrowser
    ) -> HandlerApplication {
        HandlerApplication(
            browser: browser.reference,
            applicationURL: browser.appURL
        )
    }
}

@MainActor
private final class MetadataLeaseScheduler: BrowserLeaseScheduling {
    func schedule(at deadline: Date, action: @escaping () -> Void) {}
    func cancel() {}
}
