import Foundation

struct HistoricalConfigurationSnapshot: Equatable, Identifiable, Sendable {
    var id: UUID
    var recordedAt: Date
    var configuration: RoutingConfiguration
    var changes: [String]
}

struct HistoricalRoutingEvaluation: Equatable, Sendable {
    var target: BrowserReference?
    var targetName: String?
    var reason: String

    init(
        target: BrowserReference? = nil,
        targetName: String? = nil,
        reason: String
    ) {
        self.target = target
        self.targetName = targetName
        self.reason = reason
    }
}

struct PreviewTimeMachineModel: Equatable, Sendable {
    var snapshots: [HistoricalConfigurationSnapshot]

    static func make(
        history: ConfigurationHistory,
        installedBrowsers: [InstalledBrowser],
        limit: Int = 50
    ) -> PreviewTimeMachineModel {
        let ordered = history.entries.sorted {
            if $0.recordedAt != $1.recordedAt {
                return $0.recordedAt < $1.recordedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        var previous = RoutingConfiguration.fresh
        let described = ordered.map { entry in
            defer { previous = entry.configuration }
            return HistoricalConfigurationSnapshot(
                id: entry.id,
                recordedAt: entry.recordedAt,
                configuration: entry.configuration,
                changes: changes(
                    from: previous,
                    to: entry.configuration,
                    installedBrowsers: installedBrowsers
                )
            )
        }
        return PreviewTimeMachineModel(
            snapshots: Array(described.suffix(max(0, limit))).reversed()
        )
    }

    func evaluate(
        _ rawURL: String,
        snapshotID: UUID,
        browserChange: BrowserReference,
        installedBrowsers: [InstalledBrowser]
    ) -> HistoricalRoutingEvaluation {
        guard let snapshot = snapshots.first(
            where: { $0.id == snapshotID }
        ) else {
            return HistoricalRoutingEvaluation(
                reason: "That snapshot is no longer available."
            )
        }
        guard let url = URL(string: rawURL) else {
            return HistoricalRoutingEvaluation(
                reason: "Enter an HTTP or HTTPS URL."
            )
        }
        let availableTargets = Set(
            installedBrowsers
                .filter {
                    !$0.isImaginary && $0.reference != browserChange
                }
                .map(\.reference)
        )
        let engine = RoutingEngine(
            browserChange: browserChange,
            now: { snapshot.recordedAt }
        )
        do {
            let decision = try engine.decision(
                for: url,
                configuration: snapshot.configuration,
                availableTargets: availableTargets
            )
            let targetName = installedBrowsers.first {
                $0.reference == decision.target
            }?.name ?? decision.target.bundleIdentifier
            return HistoricalRoutingEvaluation(
                target: decision.target,
                targetName: targetName,
                reason: decision.reason.summary
            )
        } catch let issue as RoutingIssue {
            return HistoricalRoutingEvaluation(
                reason: evaluationMessage(for: issue)
            )
        } catch {
            return HistoricalRoutingEvaluation(
                reason: "This historical configuration cannot route that URL."
            )
        }
    }

    private static func changes(
        from previous: RoutingConfiguration,
        to current: RoutingConfiguration,
        installedBrowsers: [InstalledBrowser]
    ) -> [String] {
        var result: [String] = []

        if previous.mode != current.mode {
            result.append(
                current.mode == .smart
                    ? "Turned Smart Routing on."
                    : "Turned Smart Routing off."
            )
        }

        if previous.fallbackBrowser != current.fallbackBrowser {
            switch (
                previous.fallbackBrowser,
                current.fallbackBrowser
            ) {
            case (.some(let old), .some(let new)):
                result.append(
                    "Fallback changed from \(browserName(old, installedBrowsers: installedBrowsers)) to \(browserName(new, installedBrowsers: installedBrowsers))."
                )
            case (.none, .some(let new)):
                result.append(
                    "Set \(browserName(new, installedBrowsers: installedBrowsers)) as the fallback."
                )
            case (.some, .none):
                result.append("Removed the external fallback.")
            case (.none, .none):
                break
            }
        }

        if previous.activeProfileID != current.activeProfileID {
            if let profileID = current.activeProfileID,
               let name = current.profiles.first(
                where: { $0.id == profileID }
               )?.name {
                result.append("Selected the \(name) profile.")
            } else {
                result.append("Returned to global rules only.")
            }
        }

        let ruleDelta = current.domainRules.count
            - previous.domainRules.count
        if ruleDelta > 0 {
            result.append(
                "Added \(ruleDelta) domain \(ruleDelta == 1 ? "rule" : "rules")."
            )
        } else if ruleDelta < 0 {
            let removed = -ruleDelta
            result.append(
                "Removed \(removed) domain \(removed == 1 ? "rule" : "rules")."
            )
        } else if current.domainRules != previous.domainRules {
            result.append("Updated domain rules.")
        }

        if previous.browserLease != current.browserLease {
            if let lease = current.browserLease {
                result.append(
                    "Started a lease for \(browserName(lease.browser, installedBrowsers: installedBrowsers))."
                )
            } else {
                result.append("Ended the browser lease.")
            }
        }

        if previous.allowAutomationLeases
            != current.allowAutomationLeases {
            result.append(
                current.allowAutomationLeases
                    ? "Allowed Shortcuts to start leases."
                    : "Stopped Shortcuts from starting leases."
            )
        }

        return result.isEmpty
            ? ["No configuration changes."]
            : result
    }

    private static func browserName(
        _ reference: BrowserReference,
        installedBrowsers: [InstalledBrowser]
    ) -> String {
        installedBrowsers.first {
            $0.reference == reference
        }?.name ?? reference.bundleIdentifier
    }

    private func evaluationMessage(
        for issue: RoutingIssue
    ) -> String {
        switch issue {
        case .unsupportedURL:
            "Enter an HTTP or HTTPS URL."
        case .smartRoutingUnavailable:
            "Smart Routing was off in this snapshot."
        case .missingFallback:
            "No currently installed browser can handle this snapshot."
        case .selfTarget:
            "This snapshot points back to BrowserChange and cannot be evaluated."
        case .duplicateDispatch, .launchFailed:
            "This historical configuration cannot route that URL."
        }
    }
}
