import Foundation

enum RoutingDecisionReason: Equatable, Sendable {
    case explicitTarget
    case activeLease(leaseID: UUID)
    case activeProfileExactHost(ruleID: UUID)
    case activeProfileParentDomain(ruleID: UUID)
    case globalExactHost(ruleID: UUID)
    case globalParentDomain(ruleID: UUID)
    case externalFallback

    var summary: String {
        switch self {
        case .explicitTarget:
            "You picked this browser"
        case .activeLease:
            "Temporary browser"
        case .activeProfileExactHost:
            "Rule for this site in the active rule set"
        case .activeProfileParentDomain:
            "Rule for this site and its subdomains in the active rule set"
        case .globalExactHost:
            "Rule for this site"
        case .globalParentDomain:
            "Rule for this site and its subdomains"
        case .externalFallback:
            "Your usual browser"
        }
    }
}

struct RoutingDecision: Equatable, Sendable {
    var target: BrowserReference
    var reason: RoutingDecisionReason
    var browserProfile: BrowserProfileChoice?

    init(
        target: BrowserReference,
        reason: RoutingDecisionReason = .externalFallback,
        browserProfile: BrowserProfileChoice? = nil
    ) {
        self.target = target
        self.reason = reason
        self.browserProfile = browserProfile
    }
}

enum RoutingIssue: Error, Equatable, Sendable {
    case unsupportedURL
    case smartRoutingUnavailable
    case missingFallback
    case selfTarget
    case explicitTargetUnavailable(BrowserReference)
    case duplicateDispatch
    case launchFailed
}

struct RoutingEngine {
    private let rillvia: BrowserReference
    private let now: () -> Date

    init(
        rillvia: BrowserReference,
        now: @escaping () -> Date = { Date() }
    ) {
        self.rillvia = rillvia
        self.now = now
    }

    func decision(
        for url: URL,
        configuration: RoutingConfiguration,
        explicitTarget: BrowserReference? = nil,
        availableTargets: Set<BrowserReference>? = nil
    ) throws -> RoutingDecision {
        // Browsers open some hosts no rule can name (such as 127.1); those skip rules instead of being dropped.
        let host: String?
        do {
            host = try URLNormalizer.normalize(url).host
        } catch URLNormalizationIssue.malformedHost {
            host = nil
        } catch {
            throw RoutingIssue.unsupportedURL
        }
        var sawSelfTarget = false
        func usable(_ target: BrowserReference) -> Bool {
            if AppIdentity.isSelf(target, reference: rillvia) {
                sawSelfTarget = true
                return false
            }
            return availableTargets?.contains(target) ?? true
        }

        if let explicitTarget {
            guard !AppIdentity.isSelf(explicitTarget, reference: rillvia),
                  availableTargets?.contains(explicitTarget) ?? true else {
                throw RoutingIssue.explicitTargetUnavailable(
                    explicitTarget
                )
            }
            return RoutingDecision(
                target: explicitTarget,
                reason: .explicitTarget
            )
        }
        guard configuration.mode == .smart else {
            throw RoutingIssue.smartRoutingUnavailable
        }

        if let lease = configuration.browserLease,
           lease.isActive(at: now()),
           usable(lease.browser) {
            return RoutingDecision(
                target: lease.browser,
                reason: .activeLease(leaseID: lease.id)
            )
        }

        let activeProfile = configuration.profiles.first {
            $0.id == configuration.activeProfileID && $0.isEnabled
        }
        if let host, let activeProfile {
            if let decision = firstDecision(
                in: configuration.domainRules,
                profileID: activeProfile.id,
                host: host,
                available: usable,
                exactReason: {
                    .activeProfileExactHost(ruleID: $0.id)
                },
                parentReason: {
                    .activeProfileParentDomain(ruleID: $0.id)
                }
            ) {
                return decision
            }
        }

        if let host, let decision = firstDecision(
            in: configuration.domainRules,
            profileID: nil,
            host: host,
            available: usable,
            exactReason: {
                .globalExactHost(ruleID: $0.id)
            },
            parentReason: {
                .globalParentDomain(ruleID: $0.id)
            }
        ) {
            return decision
        }

        if let fallback = configuration.fallbackBrowser, usable(fallback) {
            return RoutingDecision(
                target: fallback,
                reason: .externalFallback
            )
        }
        if sawSelfTarget {
            throw RoutingIssue.selfTarget
        }
        throw RoutingIssue.missingFallback
    }

    private func firstDecision(
        in rules: [DomainRule],
        profileID: UUID?,
        host: String,
        available: (BrowserReference) -> Bool,
        exactReason: (DomainRule) -> RoutingDecisionReason,
        parentReason: (DomainRule) -> RoutingDecisionReason
    ) -> RoutingDecision? {
        let matchingProfile = rules.filter {
            $0.isEnabled && $0.profileID == profileID
        }
        let exact = matchingProfile
            .filter {
                guard $0.scope == .exactHost,
                      let domain = normalizedDomain(for: $0) else {
                    return false
                }
                return URLNormalizer.host(
                        host,
                        matches: domain,
                        scope: .exactHost
                    )
            }
            .sorted(by: ruleTieBreak)

        for rule in exact where available(rule.browser) {
            return RoutingDecision(
                target: rule.browser,
                reason: exactReason(rule),
                browserProfile: rule.browserProfile
            )
        }

        let parents = matchingProfile
            .filter {
                guard $0.scope == .includeSubdomains,
                      let domain = normalizedDomain(for: $0) else {
                    return false
                }
                return URLNormalizer.host(
                        host,
                        matches: domain,
                        scope: .includeSubdomains
                    )
            }
            .sorted { lhs, rhs in
                let lhsDomain = normalizedDomain(for: lhs) ?? lhs.domain
                let rhsDomain = normalizedDomain(for: rhs) ?? rhs.domain
                let lhsLabels = lhsDomain.split(separator: ".").count
                let rhsLabels = rhsDomain.split(separator: ".").count
                if lhsLabels != rhsLabels {
                    return lhsLabels > rhsLabels
                }
                if lhsDomain.count != rhsDomain.count {
                    return lhsDomain.count > rhsDomain.count
                }
                return ruleTieBreak(lhs, rhs)
            }

        for rule in parents where available(rule.browser) {
            return RoutingDecision(
                target: rule.browser,
                reason: parentReason(rule),
                browserProfile: rule.browserProfile
            )
        }
        return nil
    }

    private func normalizedDomain(for rule: DomainRule) -> String? {
        try? URLNormalizer.normalizeHost(rule.domain)
    }

    /// Among rules for the same domain, the one saved most recently wins.
    private func ruleTieBreak(_ lhs: DomainRule, _ rhs: DomainRule) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.revision != rhs.revision {
            return lhs.revision > rhs.revision
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
