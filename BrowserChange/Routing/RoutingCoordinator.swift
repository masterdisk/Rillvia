import Foundation

protocol ExternalURLLaunching {
    func open(_ url: URL, with browser: BrowserReference) async throws
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
    }

    private let launcher: any ExternalURLLaunching
    private let engine: RoutingEngine
    private let now: () -> Date
    private let duplicateInterval: TimeInterval
    private var recentDispatches: [DispatchFingerprint: Date] = [:]

    init(
        launcher: any ExternalURLLaunching,
        browserChange: BrowserReference,
        now: @escaping () -> Date = Date.init,
        duplicateInterval: TimeInterval = 2
    ) {
        self.launcher = launcher
        self.engine = RoutingEngine(browserChange: browserChange)
        self.now = now
        self.duplicateInterval = duplicateInterval
    }

    func route(
        _ url: URL,
        configuration: RoutingConfiguration,
        explicitTarget: BrowserReference? = nil
    ) async -> RoutingOutcome {
        let decision: RoutingDecision
        do {
            decision = try engine.decision(
                for: url,
                configuration: configuration,
                explicitTarget: explicitTarget
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
        let fingerprint = DispatchFingerprint(
            urlHash: url.absoluteString.hashValue,
            target: decision.target
        )
        guard recentDispatches[fingerprint] == nil else {
            return .rejected(.duplicateDispatch)
        }
        recentDispatches[fingerprint] = timestamp

        do {
            try await launcher.open(url, with: decision.target)
            return .opened(decision.target)
        } catch {
            recentDispatches[fingerprint] = nil
            return .blocked(.launchFailed)
        }
    }

    private func disposition(for issue: RoutingIssue) -> RoutingOutcome {
        switch issue {
        case .unsupportedURL, .selfTarget, .duplicateDispatch:
            .rejected(issue)
        case .smartRoutingUnavailable, .missingFallback, .launchFailed:
            .blocked(issue)
        }
    }
}
