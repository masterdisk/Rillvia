import Foundation
import XCTest
@testable import BrowserChange

final class SystemBrowserHandlerTests: XCTestCase {
    func testPermitsBrowserChangeAsAHandlerTransactionTarget() async throws {
        let browserChange = BrowserReference(
            bundleIdentifier: "com.browserchange.BrowserChange"
        )
        let applicationURL = URL(
            fileURLWithPath: "/Applications/BrowserChange.app"
        )
        let workspace = FakeWorkspaceApplicationAccess(
            applications: [browserChange: applicationURL]
        )
        let handler = SystemBrowserHandler(
            workspace: workspace,
            browserChangeBundleIdentifier: browserChange.bundleIdentifier
        )

        try await handler.setDefaultHandler(browserChange, for: .https)

        XCTAssertEqual(
            workspace.setCalls,
            [.init(applicationURL: applicationURL, scheme: "https")]
        )
    }

    func testRejectsBrowserChangeAsAnExplicitOpenTarget() async {
        let browserChange = BrowserReference(
            bundleIdentifier: "com.browserchange.BrowserChange"
        )
        let workspace = FakeWorkspaceApplicationAccess(
            applications: [
                browserChange: URL(
                    fileURLWithPath: "/Applications/BrowserChange.app"
                ),
            ]
        )
        let handler = SystemBrowserHandler(
            workspace: workspace,
            browserChangeBundleIdentifier: browserChange.bundleIdentifier
        )

        do {
            try await handler.open(
                URL(string: "https://example.com/private?secret=value")!,
                with: browserChange
            )
            XCTFail("Expected BrowserChange to be rejected as an external target")
        } catch {
            XCTAssertEqual(
                error as? SystemBrowserHandlerError,
                .browserChangeIsNotExternalTarget
            )
        }
        XCTAssertTrue(workspace.openCalls.isEmpty)
    }

    func testExternalDispatchUsesAnExplicitApplicationURL() async throws {
        let safari = BrowserReference(
            bundleIdentifier: "com.apple.Safari"
        )
        let applicationURL = URL(
            fileURLWithPath: "/Applications/Safari.app"
        )
        let webURL = URL(string: "https://example.com/path")!
        let workspace = FakeWorkspaceApplicationAccess(
            applications: [safari: applicationURL]
        )
        let handler = SystemBrowserHandler(workspace: workspace)

        try await handler.open(webURL, with: safari)

        XCTAssertEqual(
            workspace.openCalls,
            [.init(url: webURL, applicationURL: applicationURL)]
        )
    }

    func testProfileLaunchPassesBrowserArguments() async throws {
        let chrome = BrowserReference(bundleIdentifier: "com.google.Chrome")
        let applicationURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let webURL = URL(string: "https://teams.cloud.microsoft/")!
        let workspace = FakeWorkspaceApplicationAccess(
            applications: [chrome: applicationURL]
        )
        let handler = SystemBrowserHandler(
            workspace: workspace,
            browserChangeBundleIdentifier: "com.browserchange.BrowserChange"
        )
        let work = BrowserProfileChoice(
            key: "Profile 1",
            name: "Work",
            family: .chromium
        )

        try await handler.open(webURL, with: chrome, launch: .profile(work))

        XCTAssertEqual(
            workspace.openCalls,
            [
                .init(
                    url: webURL,
                    applicationURL: applicationURL,
                    arguments: [
                        "--profile-directory=Profile 1",
                        webURL.absoluteString,
                    ]
                ),
            ]
        )
    }
}

private final class FakeWorkspaceApplicationAccess:
    WorkspaceApplicationAccess
{
    struct SetCall: Equatable {
        var applicationURL: URL
        var scheme: String
    }

    struct OpenCall: Equatable {
        var url: URL
        var applicationURL: URL
        var arguments: [String] = []
    }

    var applications: [BrowserReference: URL]
    private(set) var setCalls: [SetCall] = []
    private(set) var openCalls: [OpenCall] = []

    init(applications: [BrowserReference: URL]) {
        self.applications = applications
    }

    func applicationURL(
        forBundleIdentifier bundleIdentifier: String
    ) -> URL? {
        applications[
            BrowserReference(bundleIdentifier: bundleIdentifier)
        ]
    }

    func defaultApplicationURL(for url: URL) -> URL? {
        nil
    }

    func setDefaultApplication(
        at applicationURL: URL,
        forScheme scheme: String
    ) async throws {
        setCalls.append(
            SetCall(applicationURL: applicationURL, scheme: scheme)
        )
    }

    func open(
        _ url: URL,
        withApplicationAt applicationURL: URL
    ) async throws {
        openCalls.append(
            OpenCall(url: url, applicationURL: applicationURL)
        )
    }

    func open(
        _ url: URL,
        withApplicationAt applicationURL: URL,
        arguments: [String]
    ) async throws {
        openCalls.append(
            OpenCall(
                url: url,
                applicationURL: applicationURL,
                arguments: arguments
            )
        )
    }
}
