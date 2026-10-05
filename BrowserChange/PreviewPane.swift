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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Routing summary")
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("routing-summary-title")
                    Text("Live rules and profile state used for link predictions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(configuration.domainRules.filter(\.isEnabled).count) enabled")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
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

            SummaryRow(
                symbol: "person.crop.circle",
                title: "Active profile",
                detail: activeProfileName
            )

            if configuration.domainRules.isEmpty {
                SummaryRow(
                    symbol: "arrow.triangle.branch",
                    title: "No domain rules",
                    detail: "Unmatched links open immediately in \(store.defaultBrowserName)."
                )
            } else {
                ForEach(configuration.domainRules.prefix(4)) { rule in
                    SummaryRow(
                        symbol: rule.isEnabled
                            ? "checkmark.circle"
                            : "pause.circle",
                        title: rule.domain,
                        detail: "\(scopeName(rule.scope)) · \(store.displayName(for: rule.browser))\(rule.isEnabled ? "" : " · Disabled")"
                    )
                }
            }

            if let item = store.airlockResult.items.first,
               let decision = store.prediction(for: item) {
                SummaryRow(
                    symbol: "checkmark.shield",
                    title: "Latest Airlock prediction",
                    detail: "\(item.normalized.host) → \(store.displayName(for: decision.target)) · \(decision.reason.summary)"
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
            return "Global rules only"
        }
        return profile.name
    }

    private func scopeName(_ scope: DomainRuleScope) -> String {
        switch scope {
        case .exactHost:
            "Exact host"
        case .includeSubdomains:
            "Include subdomains"
        }
    }
}

private struct SummaryRow: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
        }
        .padding(.vertical, 12)
    }
}
