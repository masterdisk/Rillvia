import XCTest
@testable import BrowserChange

final class BrowserProfileCatalogTests: XCTestCase {
    func testChromiumProfilesUseThePersonNameAndSkipSystemEntries() throws {
        let json = """
        {
          "profile": {
            "info_cache": {
              "Default": { "name": "Person 1", "gaia_name": "Ada" },
              "Profile 1": { "name": "Work" },
              "System Profile": { "name": "System" }
            }
          }
        }
        """.data(using: .utf8)!

        let profiles = BrowserProfileCatalog.chromiumProfiles(from: json)

        XCTAssertEqual(
            profiles.map(\.name),
            ["Ada", "Work"]
        )
        XCTAssertEqual(profiles.map(\.key), ["Default", "Profile 1"])
        XCTAssertTrue(profiles.allSatisfy { $0.family == .chromium })
    }

    func testFirefoxProfilesReadNamesFromProfilesIni() {
        let text = """
        [General]
        StartWithLastProfile=1

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/abc.default-release

        [Profile1]
        Name=Work
        IsRelative=1
        Path=Profiles/def.Work
        """

        let profiles = BrowserProfileCatalog.firefoxProfiles(from: text)

        XCTAssertEqual(profiles.map(\.name), ["default-release", "Work"])
        XCTAssertTrue(profiles.allSatisfy { $0.family == .firefox })
    }

    func testLaunchArgumentsKeepANormalOpenFreeOfFlags() {
        let url = URL(string: "https://example.com")!

        XCTAssertEqual(
            BrowserProfileCatalog.launchArguments(
                bundleIdentifier: "com.google.Chrome",
                launch: .standard,
                url: url
            ),
            []
        )
    }

    func testChromeProfileAndPrivateArgumentsIncludeTheURL() {
        let url = URL(string: "https://teams.cloud.microsoft/")!
        let work = BrowserProfileChoice(
            key: "Profile 1",
            name: "Work",
            family: .chromium
        )

        XCTAssertEqual(
            BrowserProfileCatalog.launchArguments(
                bundleIdentifier: "com.google.Chrome",
                launch: .profile(work),
                url: url
            ),
            [
                "--profile-directory=Profile 1",
                "https://teams.cloud.microsoft/",
            ]
        )
        XCTAssertEqual(
            BrowserProfileCatalog.launchArguments(
                bundleIdentifier: "com.google.Chrome",
                launch: .privateWindow,
                url: url
            ),
            ["--incognito", "https://teams.cloud.microsoft/"]
        )
        XCTAssertEqual(
            BrowserProfileCatalog.launchArguments(
                bundleIdentifier: "com.microsoft.edgemac",
                launch: .privateWindow,
                url: url
            ),
            ["--inprivate", "https://teams.cloud.microsoft/"]
        )
    }

    func testFirefoxPrivateWindowUsesItsOwnFlag() {
        let url = URL(string: "https://example.com/private")!

        XCTAssertEqual(
            BrowserProfileCatalog.launchArguments(
                bundleIdentifier: "org.mozilla.firefox",
                launch: .privateWindow,
                url: url
            ),
            ["-private-window", "https://example.com/private"]
        )
    }

    @MainActor
    func testMatchedRuleCarriesItsBrowserProfileIntoTheLaunch() async throws {
        let chrome = BrowserReference(bundleIdentifier: "com.google.Chrome")
        let browserChange = BrowserReference(
            bundleIdentifier: "com.browserchange.BrowserChange"
        )
        let work = BrowserProfileChoice(
            key: "Profile 1",
            name: "Work",
            family: .chromium
        )
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: chrome,
            domainRules: [
                DomainRule(
                    domain: "teams.cloud.microsoft",
                    browser: chrome,
                    browserProfile: work
                ),
            ]
        )
        let launcher = FakeURLLauncher()
        let coordinator = RoutingCoordinator(
            launcher: launcher,
            browserChange: browserChange
        )
        let url = try XCTUnwrap(
            URL(string: "https://teams.cloud.microsoft/meeting")
        )

        let outcome = await coordinator.route(
            url,
            configuration: configuration,
            availableTargets: [chrome]
        )

        XCTAssertEqual(outcome, .opened(chrome))
        XCTAssertEqual(
            launcher.calls,
            [
                .init(
                    url: url,
                    browser: chrome,
                    launch: .profile(work)
                ),
            ]
        )
    }
}
