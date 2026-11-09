import Foundation
import XCTest
@testable import Rillvia

final class RoutingRuleEngineTests: XCTestCase {
    private let rillvia = BrowserReference(
        bundleIdentifier: "com.rillvia.app"
    )
    private let safari = BrowserReference(bundleIdentifier: "com.apple.Safari")
    private let chrome = BrowserReference(bundleIdentifier: "com.google.Chrome")
    private let firefox = BrowserReference(bundleIdentifier: "org.mozilla.firefox")
    private let profileID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000101"
    )!

    func testPrecedencePrefersActiveProfileExactThenLongestParentThenGlobal() throws {
        let profileExactID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000102"
        )!
        let profileParentID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000103"
        )!
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari,
            domainRules: [
                DomainRule(
                    domain: "example.com",
                    scope: .includeSubdomains,
                    browser: firefox,
                    profileID: profileID
                ),
                DomainRule(
                    id: profileParentID,
                    domain: "docs.example.com",
                    scope: .includeSubdomains,
                    browser: firefox,
                    profileID: profileID
                ),
                DomainRule(
                    domain: "guide.docs.example.com",
                    browser: safari
                ),
                DomainRule(
                    id: profileExactID,
                    domain: "guide.docs.example.com",
                    browser: chrome,
                    profileID: profileID
                ),
            ],
            profiles: [
                RoutingProfile(id: profileID, name: "Work"),
            ],
            activeProfileID: profileID
        )
        let engine = RoutingEngine(rillvia: rillvia)

        let exact = try engine.decision(
            for: XCTUnwrap(URL(string: "https://GUIDE.docs.example.com./path")),
            configuration: configuration,
            availableTargets: [safari, chrome, firefox]
        )
        let parent = try engine.decision(
            for: XCTUnwrap(URL(string: "https://api.docs.example.com/path")),
            configuration: configuration,
            availableTargets: [safari, chrome, firefox]
        )

        XCTAssertEqual(
            exact,
            RoutingDecision(
                target: chrome,
                reason: .activeProfileExactHost(ruleID: profileExactID)
            )
        )
        XCTAssertEqual(
            parent,
            RoutingDecision(
                target: firefox,
                reason: .activeProfileParentDomain(ruleID: profileParentID)
            )
        )
    }

    func testInactiveDisabledUnavailableAndSelfTargetsFallThrough() throws {
        let inactiveProfileID = UUID()
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari,
            domainRules: [
                DomainRule(
                    domain: "example.com",
                    browser: chrome,
                    isEnabled: false
                ),
                DomainRule(
                    domain: "example.com",
                    scope: .includeSubdomains,
                    browser: rillvia
                ),
                DomainRule(
                    domain: "example.com",
                    browser: firefox,
                    profileID: inactiveProfileID
                ),
            ],
            profiles: [
                RoutingProfile(id: inactiveProfileID, name: "Inactive"),
            ]
        )

        let decision = try RoutingEngine(rillvia: rillvia).decision(
            for: XCTUnwrap(URL(string: "https://example.com")),
            configuration: configuration,
            availableTargets: [safari, chrome]
        )

        XCTAssertEqual(
            decision,
            RoutingDecision(target: safari, reason: .externalFallback)
        )
    }

    func testExplicitTargetBeatsGlobalLeaseAndLeaseBeatsRules() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari,
            domainRules: [
                DomainRule(domain: "example.com", browser: chrome),
            ],
            browserLease: BrowserLease(
                browser: firefox,
                startedAt: now,
                expiresAt: now.addingTimeInterval(15 * 60)
            )
        )
        let engine = RoutingEngine(
            rillvia: rillvia,
            now: { now }
        )
        let url = try XCTUnwrap(URL(string: "https://example.com"))

        let explicit = try engine.decision(
            for: url,
            configuration: configuration,
            explicitTarget: firefox,
            availableTargets: [safari, chrome, firefox]
        )
        let routed = try engine.decision(
            for: url,
            configuration: configuration,
            availableTargets: [safari, chrome, firefox]
        )

        XCTAssertEqual(
            explicit,
            RoutingDecision(target: firefox, reason: .explicitTarget)
        )
        XCTAssertEqual(routed.target, firefox)
    }

    func testUnavailableExplicitTargetNeverFallsThroughToOtherRoutingLayers() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari,
            domainRules: [
                DomainRule(domain: "example.com", browser: chrome),
            ],
            browserLease: BrowserLease(
                browser: chrome,
                startedAt: now,
                expiresAt: nil
            )
        )

        XCTAssertThrowsError(
            try RoutingEngine(
                rillvia: rillvia,
                now: { now }
            ).decision(
                for: XCTUnwrap(
                    URL(string: "https://example.com/strict")
                ),
                configuration: configuration,
                explicitTarget: firefox,
                availableTargets: [safari, chrome]
            )
        ) {
            XCTAssertEqual(
                $0 as? RoutingIssue,
                .explicitTargetUnavailable(firefox)
            )
        }
    }

    func testSelfExplicitTargetNeverFallsThroughToFallback() throws {
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari
        )

        XCTAssertThrowsError(
            try RoutingEngine(
                rillvia: rillvia
            ).decision(
                for: XCTUnwrap(
                    URL(string: "https://example.com/self")
                ),
                configuration: configuration,
                explicitTarget: rillvia,
                availableTargets: [safari]
            )
        ) {
            XCTAssertEqual(
                $0 as? RoutingIssue,
                .explicitTargetUnavailable(rillvia)
            )
        }
    }

    func testExpiredAndUnavailableLeasesFallThroughAtTheExactBoundary() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let engine = RoutingEngine(
            rillvia: rillvia,
            now: { now }
        )
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari,
            domainRules: [
                DomainRule(domain: "example.com", browser: chrome),
            ],
            browserLease: BrowserLease(
                browser: firefox,
                startedAt: now.addingTimeInterval(-15 * 60),
                expiresAt: now
            )
        )

        let expired = try engine.decision(
            for: url,
            configuration: configuration,
            availableTargets: [safari, chrome, firefox]
        )
        var unavailableConfiguration = configuration
        unavailableConfiguration.browserLease = BrowserLease(
            browser: firefox,
            startedAt: now,
            expiresAt: nil
        )
        let unavailable = try engine.decision(
            for: url,
            configuration: unavailableConfiguration,
            availableTargets: [safari, chrome]
        )
        var futureConfiguration = configuration
        futureConfiguration.browserLease = BrowserLease(
            browser: firefox,
            startedAt: now.addingTimeInterval(1),
            expiresAt: now.addingTimeInterval(901)
        )
        let notStarted = try engine.decision(
            for: url,
            configuration: futureConfiguration,
            availableTargets: [safari, chrome, firefox]
        )

        XCTAssertEqual(expired.target, chrome)
        XCTAssertEqual(unavailable.target, chrome)
        XCTAssertEqual(notStarted.target, chrome)
    }

    func testExplicitChooserWorksWhenSmartRoutingIsOff() throws {
        let decision = try RoutingEngine(
            rillvia: rillvia
        ).decision(
            for: XCTUnwrap(URL(string: "https://example.com")),
            configuration: .fresh,
            explicitTarget: safari,
            availableTargets: [safari]
        )

        XCTAssertEqual(
            decision,
            RoutingDecision(target: safari, reason: .explicitTarget)
        )
    }

    func testEngineNormalizesPersistedRuleDomainsBeforeMatching() throws {
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari,
            domainRules: [
                DomainRule(
                    domain: "BÜCHER.Example.",
                    browser: chrome
                ),
            ]
        )

        let decision = try RoutingEngine(
            rillvia: rillvia
        ).decision(
            for: XCTUnwrap(URL(string: "https://xn--bcher-kva.example/path")),
            configuration: configuration,
            availableTargets: [safari, chrome]
        )

        XCTAssertEqual(decision.target, chrome)
    }

    func testHostsNoRuleCanNameSkipRulesAndUseOtherLinks() throws {
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari,
            domainRules: [DomainRule(domain: "example.com", scope: .includeSubdomains, browser: chrome)]
        )

        let decision = try RoutingEngine(rillvia: rillvia).decision(
            for: XCTUnwrap(URL(string: "http://127.1/admin")),
            configuration: configuration,
            availableTargets: [safari, chrome]
        )

        XCTAssertEqual(decision, RoutingDecision(target: safari, reason: .externalFallback))
        XCTAssertThrowsError(
            try RoutingEngine(rillvia: rillvia).decision(
                for: XCTUnwrap(URL(string: "ftp://example.com/file")),
                configuration: configuration,
                availableTargets: [safari, chrome]
            )
        ) { XCTAssertEqual($0 as? RoutingIssue, .unsupportedURL) }
    }

    func testMostRecentlySavedDuplicateRuleWinsOverMostEditedOne() throws {
        let older = Date(timeIntervalSince1970: 1_900_000_000)
        let newer = older.addingTimeInterval(60)
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari,
            domainRules: [
                DomainRule(revision: 4, domain: "example.com", browser: firefox, updatedAt: older),
                DomainRule(revision: 2, domain: "example.com", browser: chrome, updatedAt: newer),
            ]
        )

        let decision = try RoutingEngine(rillvia: rillvia).decision(
            for: XCTUnwrap(URL(string: "https://example.com")),
            configuration: configuration,
            availableTargets: [safari, chrome, firefox]
        )

        XCTAssertEqual(decision.target, chrome)
    }
}
