import Foundation
import XCTest
@testable import BrowserChange

final class SystemBrowserHandlerTests: XCTestCase {
    func testRejectsBrowserChangeAsASetTargetBeforeCallingWorkspace() async {
        let browserChange = BrowserReference(
            bundleIdentifier: "com.browserchange.BrowserChange"
        )
        let handler = SystemBrowserHandler(
            browserChangeBundleIdentifier: browserChange.bundleIdentifier
        )

        do {
            try await handler.setDefaultHandler(browserChange, for: .https)
            XCTFail("Expected BrowserChange to be rejected as an external target")
        } catch {
            XCTAssertEqual(
                error as? SystemBrowserHandlerError,
                .browserChangeIsNotExternalTarget
            )
        }
    }

    func testRejectsBrowserChangeAsAnExplicitOpenTarget() async {
        let browserChange = BrowserReference(
            bundleIdentifier: "com.browserchange.BrowserChange"
        )
        let handler = SystemBrowserHandler(
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
    }
}
