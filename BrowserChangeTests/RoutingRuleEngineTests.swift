import Foundation
import XCTest
@testable import BrowserChange

final class RoutingRuleEngineTests: XCTestCase {
    private let browserChange = BrowserReference(
        bundleIdentifier: "com.browserchange.BrowserChange"
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
        let engine = RoutingEngine(browserChange: browserChange)

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
                    browser: browserChange
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

        let decision = try RoutingEngine(browserChange: browserChange).decision(
            for: XCTUnwrap(URL(string: "https://example.com")),
            configuration: configuration,
            availableTargets: [safari, chrome]
        )

        XCTAssertEqual(
            decision,
            RoutingDecision(target: safari, reason: .externalFallback)
        )
    }

    func testExplicitTargetBeatsRulesAndLeasesDoNotAffectThisStage() throws {
        let configuration = RoutingConfiguration(
            mode: .smart,
            fallbackBrowser: safari,
            domainRules: [
                DomainRule(domain: "example.com", browser: chrome),
            ],
            leases: [
                RoutingLease(
                    domain: "example.com",
                    browser: firefox,
                    expiresAt: .distantFuture
                ),
            ]
        )
        let engine = RoutingEngine(browserChange: browserChange)
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
        XCTAssertEqual(routed.target, chrome)
    }

    func testExplicitChooserWorksWhenSmartRoutingIsOff() throws {
        let decision = try RoutingEngine(
            browserChange: browserChange
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
            browserChange: browserChange
        ).decision(
            for: XCTUnwrap(URL(string: "https://xn--bcher-kva.example/path")),
            configuration: configuration,
            availableTargets: [safari, chrome]
        )

        XCTAssertEqual(decision.target, chrome)
    }
}
