import Foundation

struct RoutingDecision: Equatable, Sendable {
    var target: BrowserReference
}

enum RoutingIssue: Error, Equatable, Sendable {
    case unsupportedURL
    case smartRoutingUnavailable
    case missingFallback
    case selfTarget
    case duplicateDispatch
    case launchFailed
}

struct RoutingEngine: Sendable {
    private let browserChange: BrowserReference

    init(browserChange: BrowserReference) {
        self.browserChange = browserChange
    }

    func decision(
        for url: URL,
        configuration: RoutingConfiguration,
        explicitTarget: BrowserReference? = nil
    ) throws -> RoutingDecision {
        guard let scheme = url.scheme?.lowercased(),
              WebScheme(rawValue: scheme) != nil,
              url.host != nil else {
            throw RoutingIssue.unsupportedURL
        }
        guard configuration.mode == .smart else {
            throw RoutingIssue.smartRoutingUnavailable
        }
        guard let target = explicitTarget ?? configuration.fallbackBrowser else {
            throw RoutingIssue.missingFallback
        }
        guard target != browserChange else {
            throw RoutingIssue.selfTarget
        }
        return RoutingDecision(target: target)
    }
}
