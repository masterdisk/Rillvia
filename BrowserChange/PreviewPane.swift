import AppKit
import SwiftUI

enum RoutingSummaryTrigger {
    static func opensTimeMachine(
        for modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        modifiers.contains(.option)
    }
}

struct RoutingSummaryView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rules")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("routing-summary-title")
                Spacer()
                Text("\(configuration.domainRules.filter(\.isEnabled).count) on")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard RoutingSummaryTrigger.opensTimeMachine(
                    for: NSEvent.modifierFlags
                ) else {
                    return
                }
                store.openTimeMachine()
            }
            .accessibilityAction(
                named: "Preview configuration history"
            ) {
                store.openTimeMachine()
            }
            .help(
                "Option-click to preview configuration history"
            )

            CallSheetRow(
                title: "Rule set",
                detail: "",
                trailing: activeProfileName
            )

            if configuration.domainRules.isEmpty {
                CallSheetRow(
                    title: "No rules",
                    detail: "Other links open in \(store.defaultBrowserName).",
                    trailing: ""
                )
            } else {
                ForEach(configuration.domainRules.prefix(6)) { rule in
                    CallSheetRow(
                        title: rule.domain,
                        detail: rule.isEnabled
                            ? scopeName(rule.scope)
                            : "\(scopeName(rule.scope)), off",
                        trailing: store.displayName(for: rule.browser)
                    )
                }
            }

            if let item = store.airlockResult.items.first,
               let decision = store.prediction(for: item) {
                CallSheetRow(
                    title: item.normalized.host,
                    detail: decision.reason.summary,
                    trailing: store.displayName(for: decision.target)
                )
            }
        }
    }

    private var configuration: RoutingConfiguration {
        store.routingConfiguration
    }

    private var activeProfileName: String {
        guard let activeProfileID = configuration.activeProfileID,
              let profile = configuration.profiles.first(
                where: { $0.id == activeProfileID }
              ) else {
            return "Everywhere"
        }
        return profile.name
    }

    private func scopeName(_ scope: DomainRuleScope) -> String {
        switch scope {
        case .exactHost:
            "This site"
        case .includeSubdomains:
            "This site and subdomains"
        }
    }
}

