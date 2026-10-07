import AppKit
import Foundation

struct DiagnosticsSection: Equatable, Identifiable, Sendable {
    var title: String
    var lines: [String]

    var id: String {
        title
    }
}

struct DiagnosticsSnapshot: Equatable, Sendable {
    var sections: [DiagnosticsSection]

    var visibleText: String {
        (
            [
                "Rillvia — Redacted Diagnostics",
                "URLs, paths, queries, clipboard contents, cookies, and browsing history are excluded.",
            ]
            + sections.flatMap { section in
                ["", section.title] + section.lines
            }
        )
        .joined(separator: "\n")
    }

    @MainActor
    func copy(to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(visibleText, forType: .string)
    }

    static func make(
        appName: String,
        appVersion: String,
        buildVersion: String,
        rillvia: BrowserReference,
        handlers: HTTPHandlerSnapshot,
        routingState: BrowserRoutingState,
        configuration: RoutingConfiguration,
        journal: HandlerOperationJournal,
        historySchemaVersion: Int =
            ConfigurationHistory.currentSchemaVersion,
        canUndo: Bool,
        installedBrowsers: [InstalledBrowser],
        now: Date
    ) -> DiagnosticsSnapshot {
        let app = DiagnosticsSection(
            title: "App",
            lines: [
                "\(appName) \(appVersion) (\(buildVersion))",
                "Configuration schema: \(configuration.schemaVersion)",
                "Handler journal schema: \(journal.schemaVersion)",
                "History schema: \(historySchemaVersion)",
            ]
        )

        let handlerLines = WebScheme.allCases.map { scheme in
            handlerLine(
                scheme: scheme,
                application: handlers[scheme],
                rillvia: rillvia
            )
        } + [
            "Ownership health: \(ownershipSummary(handlers, rillvia: rillvia))",
        ]

        let activeProfile = configuration.activeProfileID.flatMap { id in
            configuration.profiles.first { $0.id == id }?.name
        } ?? "Global rules only"
        let enabledRuleCount = configuration.domainRules.filter(
            \.isEnabled
        ).count
        let fallback = configuration.fallbackBrowser.map {
            browserDescription(
                $0,
                installedBrowsers: installedBrowsers
            )
        } ?? "None"
        let lease = configuration.browserLease.map {
            leaseDescription(
                $0,
                installedBrowsers: installedBrowsers,
                now: now
            )
        } ?? "None"
        let routing = DiagnosticsSection(
            title: "Routing",
            lines: [
                "Routing mode: \(configuration.mode == .smart ? "Smart" : "Direct")",
                "Routing state: \(routingStateSummary(routingState))",
                "External fallback: \(fallback)",
                "Active profile: \(activeProfile)",
                "Rules: \(enabledRuleCount) enabled, \(configuration.domainRules.count) total",
                "Temporary browser: \(lease)",
            ]
        )

        var operationLines: [String]
        if let operation = journal.pendingOperation {
            operationLines = [
                "Pending operation: \(operationTitle(operation.kind))",
                "Progress: \(operation.completedSchemes.count) of \(WebScheme.allCases.count) handlers complete",
                "In flight: \(operation.inFlightScheme.map { $0.rawValue.uppercased() } ?? "None")",
            ]
        } else {
            operationLines = ["Pending operation: None"]
        }
        operationLines.append(
            "Undo available: \(canUndo ? "Yes" : "No")"
        )
        let operations = DiagnosticsSection(
            title: "Handler operation",
            lines: operationLines
        )

        let browserLines = installedBrowsers
            .filter { !$0.isImaginary }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
            .map {
                "\($0.name) \($0.version) — \($0.id)"
            }
        let browsers = DiagnosticsSection(
            title: "Installed browsers",
            lines: browserLines.isEmpty ? ["None"] : browserLines
        )

        return DiagnosticsSnapshot(
            sections: [app, DiagnosticsSection(
                title: "Web handlers",
                lines: handlerLines
            ), routing, operations, browsers]
        )
    }

    private static func handlerLine(
        scheme: WebScheme,
        application: HandlerApplication?,
        rillvia: BrowserReference
    ) -> String {
        let prefix = scheme.rawValue.uppercased()
        guard let application else {
            return "\(prefix): missing"
        }
        let owner = application.browser == rillvia
            ? "Rillvia"
            : "external"
        return "\(prefix): \(application.browser.bundleIdentifier) — \(owner)"
    }

    private static func ownershipSummary(
        _ handlers: HTTPHandlerSnapshot,
        rillvia: BrowserReference
    ) -> String {
        switch handlers.ownership(rillvia: rillvia) {
        case .external:
            "healthy external"
        case .rillvia:
            "healthy Rillvia"
        case .split:
            "split"
        case .missing:
            "missing"
        }
    }

    private static func routingStateSummary(
        _ state: BrowserRoutingState
    ) -> String {
        switch state {
        case .direct:
            "Direct"
        case .enabling:
            "Enabling"
        case .smartActive:
            "Active"
        case .smartSuspended:
            "Suspended"
        case .disabling:
            "Disabling"
        case .degraded:
            "Degraded"
        }
    }

    private static func browserDescription(
        _ reference: BrowserReference,
        installedBrowsers: [InstalledBrowser]
    ) -> String {
        let name = installedBrowsers.first {
            $0.reference == reference
        }?.name ?? reference.bundleIdentifier
        return "\(name) (\(reference.bundleIdentifier))"
    }

    private static func leaseDescription(
        _ lease: BrowserLease,
        installedBrowsers: [InstalledBrowser],
        now: Date
    ) -> String {
        let browser = browserDescription(
            lease.browser,
            installedBrowsers: installedBrowsers
        )
        guard lease.isActive(at: now) else {
            return "\(browser), expired"
        }
        guard lease.expiresAt != nil else {
            return "\(browser), until you stop"
        }
        return "\(browser), \(BrowserLeaseFormatting.remainingText(for: lease, at: now))"
    }

    private static func operationTitle(
        _ kind: HandlerOperationKind
    ) -> String {
        switch kind {
        case .direct:
            "Direct switch"
        case .undo:
            "Undo"
        case .smartActivation:
            "Smart activation"
        case .smartDeactivation:
            "Smart deactivation"
        }
    }
}
