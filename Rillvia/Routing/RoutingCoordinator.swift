import Foundation

protocol ExternalURLLaunching {
    func open(_ url: URL, with browser: BrowserReference) async throws
    func open(
        _ url: URL,
        with browser: BrowserReference,
        launch: BrowserLaunchMode
    ) async throws
}

extension ExternalURLLaunching {
    func open(
        _ url: URL,
        with browser: BrowserReference,
        launch: BrowserLaunchMode
    ) async throws {
        try await open(url, with: browser)
    }
}

enum RoutingOutcome: Equatable, Sendable {
    case opened(BrowserReference)
    case rejected(RoutingIssue)
    case blocked(RoutingIssue)
}

@MainActor
final class RoutingCoordinator {
    private struct DispatchFingerprint: Hashable {
        var urlHash: Int
        var target: BrowserReference
        var launchKey: String
    }

    private let launcher: any ExternalURLLaunching
    private let engine: RoutingEngine
    private let now: () -> Date
    private let duplicateInterval: TimeInterval
    private var recentDispatches: [DispatchFingerprint: Date] = [:]

    init(
        launcher: any ExternalURLLaunching,
        rillvia: BrowserReference,
        now: @escaping () -> Date = Date.init,
        duplicateInterval: TimeInterval = 2
    ) {
        self.launcher = launcher
        self.engine = RoutingEngine(
            rillvia: rillvia,
            now: now
        )
        self.now = now
        self.duplicateInterval = duplicateInterval
    }

    func route(
        _ url: URL,
        configuration: RoutingConfiguration,
        explicitTarget: BrowserReference? = nil,
        availableTargets: Set<BrowserReference>? = nil,
        explicitLaunch: BrowserLaunchMode = .standard
    ) async -> RoutingOutcome {
        let decision: RoutingDecision
        do {
            decision = try engine.decision(
                for: url,
                configuration: configuration,
                explicitTarget: explicitTarget,
                availableTargets: availableTargets
            )
        } catch let issue as RoutingIssue {
            return disposition(for: issue)
        } catch {
            return .blocked(.launchFailed)
        }

        let timestamp = now()
        recentDispatches = recentDispatches.filter {
            timestamp.timeIntervalSince($0.value) < duplicateInterval
        }
        let launch = resolvedLaunch(
            explicitLaunch: explicitLaunch,
            decision: decision
        )
        let fingerprint = DispatchFingerprint(
            urlHash: url.absoluteString.hashValue,
            target: decision.target,
            launchKey: launchKey(for: launch)
        )
        guard recentDispatches[fingerprint] == nil else {
            return .rejected(.duplicateDispatch)
        }
        recentDispatches[fingerprint] = timestamp

        do {
            try await launcher.open(
                url,
                with: decision.target,
                launch: launch
            )
            return .opened(decision.target)
        } catch {
            recentDispatches[fingerprint] = nil
            return .blocked(.launchFailed)
        }
    }

    func decision(
        for url: URL,
        configuration: RoutingConfiguration,
        explicitTarget: BrowserReference? = nil,
        availableTargets: Set<BrowserReference>? = nil
    ) throws -> RoutingDecision {
        try engine.decision(
            for: url,
            configuration: configuration,
            explicitTarget: explicitTarget,
            availableTargets: availableTargets
        )
    }

    private func resolvedLaunch(
        explicitLaunch: BrowserLaunchMode,
        decision: RoutingDecision
    ) -> BrowserLaunchMode {
        if explicitLaunch != .standard {
            return explicitLaunch
        }
        if let profile = decision.browserProfile {
            return .profile(profile)
        }
        return .standard
    }

    private func launchKey(for launch: BrowserLaunchMode) -> String {
        switch launch {
        case .standard:
            "standard"
        case .privateWindow:
            "private"
        case .profile(let profile):
            profile.id
        }
    }

    private func disposition(for issue: RoutingIssue) -> RoutingOutcome {
        switch issue {
        case .unsupportedURL, .selfTarget, .explicitTargetUnavailable,
                .duplicateDispatch:
            .rejected(issue)
        case .smartRoutingUnavailable, .missingFallback, .launchFailed:
            .blocked(issue)
        }
    }
}
