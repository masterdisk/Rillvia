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
        let retained = ordered.suffix(max(0, limit))
        var previous: RoutingConfiguration?
        let described = retained.map { entry in
            let description = previous.map {
                changes(
                    from: $0,
                    to: entry.configuration,
                    installedBrowsers: installedBrowsers
                )
            } ?? [
                "Oldest retained snapshot. Earlier changes are unavailable.",
            ]
            previous = entry.configuration
            return HistoricalConfigurationSnapshot(
                id: entry.id,
                recordedAt: entry.recordedAt,
                configuration: entry.configuration,
                changes: description
            )
        }
        return PreviewTimeMachineModel(
            snapshots: described.reversed()
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
                    ? "Started sending links through Linkpick."
                    : "Stopped sending links through Linkpick."
            )
        }

        if previous.fallbackBrowser != current.fallbackBrowser {
            switch (
                previous.fallbackBrowser,
                current.fallbackBrowser
            ) {
            case (.some(let old), .some(let new)):
                result.append(
                    "The browser for sites with no rule changed from \(browserName(old, installedBrowsers: installedBrowsers)) to \(browserName(new, installedBrowsers: installedBrowsers))."
                )
            case (.none, .some(let new)):
                result.append(
                    "Set \(browserName(new, installedBrowsers: installedBrowsers)) as the browser for sites with no rule."
                )
            case (.some, .none):
                result.append("Removed the browser for sites with no rule.")
            case (.none, .none):
                break
            }
        }

        result.append(
            contentsOf: profileChanges(
                from: previous.profiles,
                to: current.profiles,
                installedBrowsers: installedBrowsers
            )
        )

        if previous.activeProfileID != current.activeProfileID {
            if let profileID = current.activeProfileID,
               let name = current.profiles.first(
                where: { $0.id == profileID }
               )?.name {
                result.append("Selected the \(name) rule set.")
            } else {
                result.append("Using rules that apply everywhere.")
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
                    "Started using \(browserName(lease.browser, installedBrowsers: installedBrowsers)) for a while."
                )
            } else {
                result.append("Stopped the temporary browser.")
            }
        }

        if previous.allowAutomationLeases
            != current.allowAutomationLeases {
            result.append(
                current.allowAutomationLeases
                    ? "Allowed Shortcuts to switch browsers."
                    : "Stopped Shortcuts from switching browsers."
            )
        }

        return result.isEmpty
            ? ["No configuration changes."]
            : result
    }

    private static func profileChanges(
        from previous: [RoutingProfile],
        to current: [RoutingProfile],
        installedBrowsers: [InstalledBrowser]
    ) -> [String] {
        let previousByID = Dictionary(
            previous.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentByID = Dictionary(
            current.map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last }
        )
        var result: [String] = []

        for profile in previous
            .filter({ currentByID[$0.id] == nil })
            .sorted(by: profileComesBefore) {
            result.append("Removed the \(profile.name) rule set.")
        }

        for profile in current
            .filter({ previousByID[$0.id] == nil })
            .sorted(by: profileComesBefore) {
            result.append("Added the \(profile.name) rule set.")
        }

        let retainedProfiles = current
            .filter { previousByID[$0.id] != nil }
            .sorted(by: profileComesBefore)
        for profile in retainedProfiles {
            guard let old = previousByID[profile.id],
                  old != profile else {
                continue
            }

            var describedVisibleChange = false
            if old.name != profile.name {
                result.append(
                    "Renamed the \(old.name) rule set to \(profile.name)."
                )
                describedVisibleChange = true
            }
            if old.isEnabled != profile.isEnabled {
                result.append(
                    profile.isEnabled
                        ? "Enabled the \(profile.name) rule set."
                        : "Disabled the \(profile.name) rule set."
                )
                describedVisibleChange = true
            }
            if old.browser != profile.browser {
                switch (old.browser, profile.browser) {
                case (.some(let oldBrowser), .some(let newBrowser)):
                    result.append(
                        "Changed the browser for the \(profile.name) rule set from \(browserName(oldBrowser, installedBrowsers: installedBrowsers)) to \(browserName(newBrowser, installedBrowsers: installedBrowsers))."
                    )
                case (.none, .some(let browser)):
                    result.append(
                        "Set \(browserName(browser, installedBrowsers: installedBrowsers)) as the browser for the \(profile.name) rule set."
                    )
                case (.some, .none):
                    result.append(
                        "Removed the browser from the \(profile.name) rule set."
                    )
                case (.none, .none):
                    break
                }
                describedVisibleChange = true
            }

            let hasOtherChange = old.source != profile.source
                || old.createdAt != profile.createdAt
                || (!describedVisibleChange
                    && (old.revision != profile.revision
                        || old.updatedAt != profile.updatedAt))
            if hasOtherChange || !describedVisibleChange {
                result.append("Updated the \(profile.name) rule set.")
            }
        }

        return result
    }

    private static func profileComesBefore(
        _ lhs: RoutingProfile,
        _ rhs: RoutingProfile
    ) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        return comparison == .orderedSame
            ? lhs.id.uuidString < rhs.id.uuidString
            : comparison == .orderedAscending
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
            "Linkpick was not sending links in this snapshot."
        case .missingFallback:
            "No installed browser can open this link in this snapshot."
        case .selfTarget:
            "This snapshot points back to Linkpick and cannot be checked."
        case .explicitTargetUnavailable:
            "The selected browser is no longer available."
        case .duplicateDispatch, .launchFailed:
            "This historical configuration cannot route that URL."
        }
    }
}
