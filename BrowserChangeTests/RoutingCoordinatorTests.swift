import Foundation
import XCTest
@testable import BrowserChange

@MainActor
final class RoutingCoordinatorTests: XCTestCase {
    private let browserChange = BrowserReference(
        bundleIdentifier: "com.browserchange.BrowserChange"
    )
    private let safari = BrowserReference(
        bundleIdentifier: "com.apple.Safari"
    )
    private let chrome = BrowserReference(
        bundleIdentifier: "com.google.Chrome"
    )
    private let webURL = URL(
        string: "https://example.com/private/path?secret=value"
    )!

    func testEngineRoutesHTTPAndHTTPSURLsToFallbackWithoutRulesOrChooser() throws {
        let engine = RoutingEngine(browserChange: browserChange)
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari
        )

        for url in [
            URL(string: "http://example.com/plain")!,
            webURL,
        ] {
            let decision = try engine.decision(
                for: url,
                configuration: configuration
            )
            XCTAssertEqual(decision, RoutingDecision(target: safari))
        }
    }

    func testEngineHonorsExplicitExternalTargetForFutureCallers() throws {
        let engine = RoutingEngine(browserChange: browserChange)
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari
        )

        let decision = try engine.decision(
            for: webURL,
            configuration: configuration,
            explicitTarget: chrome
        )

        XCTAssertEqual(
            decision,
            RoutingDecision(target: chrome, reason: .explicitTarget)
        )
    }

    func testEngineRejectsUnsupportedSchemeSelfTargetAndMissingFallback() {
        let engine = RoutingEngine(browserChange: browserChange)

        XCTAssertThrowsError(
            try engine.decision(
                for: URL(string: "file:///tmp/private.txt")!,
                configuration: .init(mode: .smart, fallbackBrowser: safari)
            )
        ) {
            XCTAssertEqual($0 as? RoutingIssue, .unsupportedURL)
        }
        XCTAssertThrowsError(
            try engine.decision(
                for: webURL,
                configuration: .init(
                    mode: .smart,
                    fallbackBrowser: browserChange
                )
            )
        ) {
            XCTAssertEqual($0 as? RoutingIssue, .selfTarget)
        }
        XCTAssertThrowsError(
            try engine.decision(
                for: webURL,
                configuration: .init(mode: .smart)
            )
        ) {
            XCTAssertEqual($0 as? RoutingIssue, .missingFallback)
        }
    }

    func testCoordinatorExplicitlyLaunchesFallbackAndGuardsDuplicateBounce() async {
        let launcher = RecordingURLLauncher()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let coordinator = RoutingCoordinator(
            launcher: launcher,
            browserChange: browserChange,
            now: { now }
        )
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari
        )

        let first = await coordinator.route(
            webURL,
            configuration: configuration
        )
        let duplicate = await coordinator.route(
            webURL,
            configuration: configuration
        )

        XCTAssertEqual(first, .opened(safari))
        XCTAssertEqual(duplicate, .rejected(.duplicateDispatch))
        XCTAssertEqual(
            launcher.calls,
            [.init(url: webURL, browser: safari)]
        )
    }

    func testCoordinatorFailsClosedWhenFallbackCannotLaunch() async {
        let launcher = RecordingURLLauncher()
        launcher.error = TestLaunchError.unavailable
        let coordinator = RoutingCoordinator(
            launcher: launcher,
            browserChange: browserChange
        )
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari
        )

        let outcome = await coordinator.route(
            webURL,
            configuration: configuration
        )

        XCTAssertEqual(outcome, .blocked(.launchFailed))
        XCTAssertEqual(launcher.calls.count, 1)
    }
}

@MainActor
final class IncomingURLQueueTests: XCTestCase {
    func testColdLaunchURLWaitsForAttachmentAndInitializationBeforeDraining() async {
        let queue = IncomingURLQueue()
        let url = URL(string: "https://example.com/cold-launch")!
        var received: [URL] = []

        queue.enqueue([url])
        XCTAssertEqual(queue.pendingCount, 1)

        queue.attach { incomingURL in
            received.append(incomingURL)
            return .consumed
        }
        XCTAssertTrue(received.isEmpty)
        XCTAssertEqual(queue.pendingCount, 1)

        await queue.drain()

        XCTAssertEqual(received, [url])
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testBlockedURLRemainsQueuedAndIsRetriedWithoutBeingDropped() async {
        let queue = IncomingURLQueue()
        let url = URL(string: "https://example.com/retry")!
        var shouldRetry = true
        var attempts = 0
        queue.attach { _ in
            attempts += 1
            if shouldRetry {
                return .retryLater
            }
            return .consumed
        }
        queue.enqueue([url])

        await queue.drain()

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(queue.pendingCount, 1)

        shouldRetry = false
        await queue.drain()

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(queue.pendingCount, 0)
    }
}

private enum TestLaunchError: Error {
    case unavailable
}

@MainActor
private final class RecordingURLLauncher: ExternalURLLaunching {
    struct Call: Equatable {
        var url: URL
        var browser: BrowserReference
    }

    var error: Error?
    private(set) var calls: [Call] = []

    func open(_ url: URL, with browser: BrowserReference) async throws {
        calls.append(Call(url: url, browser: browser))
        if let error {
            throw error
        }
    }
}
