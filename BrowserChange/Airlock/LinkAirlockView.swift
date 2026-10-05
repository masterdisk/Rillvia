import SwiftUI

struct LinkAirlockView: View {
    @Environment(BrowserStore.self) private var store
    @State private var input = ""
    @State private var chooserItem: AirlockItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Link Airlock")
                        .font(.system(size: 30, weight: .semibold))
                        .accessibilityIdentifier("airlock-title")
                    Text(
                        "Inspect links and their predicted browser before anything opens."
                    )
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $input)
                        .font(.body.monospaced())
                        .frame(minHeight: 92)
                        .padding(6)
                        .background(
                            .quaternary.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .accessibilityIdentifier("airlock-input")

                    HStack {
                        Button("Preview links", systemImage: "checkmark.shield") {
                            store.stageAirlock(text: input)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("airlock-preview")

                        Button("Clear") {
                            input = ""
                            store.clearAirlock()
                        }
                        .disabled(input.isEmpty && store.airlockResult.items.isEmpty)

                        Spacer()

                        Text(
                            "Up to \(AirlockParser.defaultMaxURLCount) links · \(AirlockParser.defaultMaxTextLength.formatted()) characters"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    store.stageAirlock(urls: urls)
                    return true
                }
                .dropDestination(for: String.self) { strings, _ in
                    store.stageAirlock(text: strings.joined(separator: "\n"))
                    return true
                }

                if store.airlockResult.wasTextTruncated {
                    Label(
                        "Only the first \(AirlockParser.defaultMaxTextLength.formatted()) characters were inspected.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if store.airlockResult.wasURLLimitReached {
                    Label(
                        "Additional links were left unstaged.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if store.airlockResult.rejectedCandidateCount > 0 {
                    Label(
                        "\(store.airlockResult.rejectedCandidateCount) unsupported or malformed link candidate\(store.airlockResult.rejectedCandidateCount == 1 ? " was" : "s were") ignored.",
                        systemImage: "xmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(store.airlockResult.items) { item in
                        AirlockItemCard(item: item) {
                            chooserItem = item
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $chooserItem) { item in
            BrowserChooserView(item: item)
        }
    }
}

private struct AirlockItemCard: View {
    @Environment(BrowserStore.self) private var store
    var item: AirlockItem
    var showChooser: () -> Void

    var body: some View {
        let decision = store.prediction(for: item)

        VStack(alignment: .leading, spacing: 12) {
            Text(item.originalText)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)

            LabeledContent("Normalized host") {
                Text(item.normalized.host)
                    .font(.body.weight(.medium))
                    .textSelection(.enabled)
            }

            LabeledContent("Predicted browser") {
                if let decision {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(store.displayName(for: decision.target))
                            .font(.body.weight(.medium))
                        Text(decision.reason.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Smart Routing unavailable")
                        .foregroundStyle(.secondary)
                }
            }

            if !item.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(item.warnings.enumerated()), id: \.offset) {
                        _, warning in
                        Label(
                            warning.message,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            }

            HStack {
                Button("Open now") {
                    Task { await store.openAirlockNow(item) }
                }
                .buttonStyle(.glassProminent)
                .disabled(decision == nil)

                Button("Open in…") {
                    showChooser()
                }
                .accessibilityIdentifier("airlock-open-in")
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary)
        }
    }
}

private struct BrowserChooserView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var item: AirlockItem

    @State private var alwaysOpen = false
    @State private var scope: DomainRuleScope = .exactHost
    @State private var profileID: UUID?
    @State private var errorMessage: String?
    @State private var isOpening = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open in…")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier(
                        "browser-chooser-title"
                    )
                Text(item.normalized.host)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }

            Toggle("Always open this domain here", isOn: $alwaysOpen)
                .accessibilityIdentifier("chooser-always")

            if alwaysOpen {
                Picker("Match", selection: $scope) {
                    Text("Exact host").tag(DomainRuleScope.exactHost)
                    Text("Include subdomains").tag(
                        DomainRuleScope.includeSubdomains
                    )
                }
                .pickerStyle(.radioGroup)

                Picker("Rule owner", selection: $profileID) {
                    Text("Global").tag(UUID?.none)
                    ForEach(store.routingConfiguration.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
            }

            if let errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("chooser-error")
                .accessibilityLabel(errorMessage)
            }

            Divider()

            ForEach(store.externalBrowsers) { browser in
                Button {
                    let teachingScope = alwaysOpen ? scope : nil
                    isOpening = true
                    errorMessage = nil
                    Task {
                        let result = await store
                            .openAirlockFromChooser(
                                item,
                                in: browser.reference,
                                always: teachingScope,
                                profileID: alwaysOpen
                                    ? profileID
                                    : nil
                            )
                        isOpening = false
                        if result.shouldDismiss {
                            dismiss()
                        } else {
                            errorMessage = result.errorMessage
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: store.icon(for: browser))
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text("Open in \(browser.name)")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isOpening)
                .accessibilityIdentifier("chooser-open-\(browser.name)")
            }

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .disabled(isOpening)
        }
        .padding(24)
        .frame(width: 420)
        .onChange(of: alwaysOpen) {
            if !alwaysOpen {
                errorMessage = nil
            }
        }
    }
}
