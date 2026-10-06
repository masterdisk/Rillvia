import SwiftUI

struct LinkAirlockView: View {
    @Environment(BrowserStore.self) private var store
    @State private var input = ""
    @State private var chooserItem: AirlockItem?

    var body: some View {
        LinkpickPage(title: "Check a link", identifier: "airlock-title") {
            Section {
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
                        .buttonStyle(.borderedProminent)
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
        }
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

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.normalized.host)
                        .font(.body.weight(.semibold))
                        .textSelection(.enabled)
                    if let decision {
                        Text(store.displayName(for: decision.target))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("airlock-predicted-browser")
                        Text(decision.reason.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Linkpick is not sending links")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
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
                .buttonStyle(.borderedProminent)
                .disabled(decision == nil)

                Button("Open in…") {
                    showChooser()
                }
                .accessibilityIdentifier("airlock-open-in")
            }
        }
        .padding(.vertical, 8)
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

            Toggle("Always open this site here", isOn: $alwaysOpen)
                .accessibilityIdentifier("chooser-always")

            if alwaysOpen {
                Picker("Match", selection: $scope) {
                    Text("This site").tag(DomainRuleScope.exactHost)
                    Text("This site and subdomains").tag(
                        DomainRuleScope.includeSubdomains
                    )
                }
                .pickerStyle(.radioGroup)

                Picker("Rule set", selection: $profileID) {
                    Text("Everywhere").tag(UUID?.none)
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
                chooserButton(
                    title: "Open in \(browser.name)",
                    identifier: "chooser-open-\(browser.name)",
                    browser: browser,
                    launch: .standard
                )

                let profiles = store.browserProfiles(for: browser.id)
                if profiles.count > 1 {
                    ForEach(profiles) { profile in
                        chooserButton(
                            title: "Open in \(browser.name) · \(profile.name)",
                            identifier: "chooser-profile-\(browser.name)-\(profile.key)",
                            browser: browser,
                            launch: .profile(profile)
                        )
                    }
                }

                if store.supportsPrivateWindow(browser.id) {
                    chooserButton(
                        title: "Open in \(browser.name) private",
                        identifier: "chooser-private-\(browser.name)",
                        browser: browser,
                        launch: .privateWindow
                    )
                }
            }

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .disabled(isOpening)
        }
        .padding(24)
        .frame(width: 480)
        .onChange(of: alwaysOpen) {
            if !alwaysOpen {
                errorMessage = nil
            }
        }
    }

    private func chooserButton(
        title: String,
        identifier: String,
        browser: InstalledBrowser,
        launch: BrowserLaunchMode
    ) -> some View {
        Button {
            let teachingScope = alwaysOpen ? scope : nil
            isOpening = true
            errorMessage = nil
            Task {
                let result = await store.openAirlockFromChooser(
                    item,
                    in: browser.reference,
                    always: teachingScope,
                    profileID: alwaysOpen ? profileID : nil,
                    launch: launch
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
                Text(title)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(isOpening)
        .accessibilityIdentifier(identifier)
    }
}
