import SwiftUI

struct BrowserSidebar: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        List {
            Section {
                WorkspaceNavigationRow(
                    destination: .direct,
                    title: "Browsers",
                    systemImage: "arrow.up.right.square"
                )
                WorkspaceNavigationRow(
                    destination: .airlock,
                    title: "Check a link",
                    systemImage: "checkmark.shield"
                )
                WorkspaceNavigationRow(
                    destination: .rules,
                    title: "Rules",
                    systemImage: "arrow.triangle.branch"
                )
                WorkspaceNavigationRow(
                    destination: .profiles,
                    title: "Rule sets",
                    systemImage: "person.2"
                )
            }

            Section {
                ForEach(store.browsers) { browser in
                    Button {
                        store.selectBrowser(browser.id)
                    } label: {
                        BrowserSidebarRow(browser: browser)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "browser-row-\(browser.name)"
                    )
                    .accessibilityLabel(browser.name)
                    .accessibilityValue(
                        browser.id == store.defaultBundleID
                            ? "\(browser.version), \(store.isSmartRoutingConfigured ? "browser for sites with no rule" : "usual browser")"
                            : browser.version
                    )
                    .accessibilityAddTraits(
                        store.workspaceDestination == .direct
                            && store.selectedID == browser.id
                            ? .isSelected
                            : []
                    )
                    .listRowBackground(
                        store.workspaceDestination == .direct
                            && store.selectedID == browser.id
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear
                    )
                }
            } header: {
                Button("Installed") {
                    store.tapTitle()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("browsers-header")
                .accessibilityHint(
                    "Press five times quickly to open the Living Browser Hall."
                )
                .help(
                    "Five quick presses open the Living Browser Hall"
                )
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("browser-sidebar")
    }
}

private struct WorkspaceNavigationRow: View {
    @Environment(BrowserStore.self) private var store
    var destination: WorkspaceDestination
    var title: String
    var systemImage: String

    var body: some View {
        Button {
            store.showWorkspace(destination)
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            store.workspaceDestination == destination
                ? Color.accentColor.opacity(0.14)
                : Color.clear
        )
        .accessibilityIdentifier("nav-\(destination.rawValue)")
    }
}

private struct BrowserSidebarRow: View {
    @Environment(BrowserStore.self) private var store
    var browser: InstalledBrowser

    var body: some View {
        let isDefault = browser.id == store.defaultBundleID

        HStack(spacing: 10) {
            Image(nsImage: store.icon(for: browser))
                .resizable()
                .interpolation(.medium)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(browser.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(browser.version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            if isDefault {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                    .accessibilityLabel(
                        store.isSmartRoutingConfigured
                            ? "Browser for sites with no rule"
                            : "Usual browser"
                    )
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel(browser.name)
        .accessibilityValue(
            isDefault
                ? "\(browser.version), \(store.isSmartRoutingConfigured ? "browser for sites with no rule" : "usual browser")"
                : browser.version
        )
    }
}

struct BrowserWorkspace: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        Group {
            switch store.workspaceDestination {
            case .direct:
                DirectWorkspace()
            case .airlock:
                LinkAirlockView()
            case .rules:
                RulesView()
            case .profiles:
                ProfilesView()
            }
        }
        .id(store.workspaceDestination)
    }
}

private struct DirectWorkspace: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        Form {
            if let browser = store.browsers.first(where: { $0.id == store.selectedID }) {
                Section {
                    BrowserHeading(browser: browser)
                    RoutingModeRows()
                    if store.activeBrowserLease != nil || store.canUndoLease {
                        BrowserLeaseRows()
                    }
                    HandlerTransactionControls()
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct BrowserHeading: View {
    @Environment(BrowserStore.self) private var store
    var browser: InstalledBrowser

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: store.icon(for: browser))
                .resizable()
                .interpolation(.medium)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(browser.name)
                    .font(.headline)
                    .accessibilityIdentifier("workspace-title")
                Text(browser.version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
    }
}

private struct RoutingModeRows: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let fallback = store.smartFallbackBrowser
            ?? store.switchable.first { $0.id == store.defaultBundleID }
        let browser = store.browsers.first { $0.id == store.selectedID }

        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(store.routingModeTitle)
                    .accessibilityIdentifier("routing-mode-title")
                Spacer()
                Text(modeBadge)
                    .font(.caption)
                    .foregroundStyle(modeColor)
            }
            Text(store.routingModeDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("routing-mode-detail")
        }

        if let browser, browser.id != store.defaultBundleID, !browser.isImaginary {
            if store.isSmartRoutingConfigured {
                Button("Use \(browser.name) when no rule matches") {
                    Task { await store.makeDefault(browser) }
                }
                .disabled(store.isSwitching)
            } else {
                Button("Make \(browser.name) the usual browser") {
                    Task { await store.makeDefault(browser) }
                }
                .disabled(store.isSwitching)
                .keyboardShortcut(.defaultAction)
            }
        }

        if let browser, store.isSmartRoutingActive, !browser.isImaginary {
            Menu {
                ForEach(BrowserLeasePreset.allCases) { preset in
                    Button(preset.title) {
                        store.borrowBrowser(browser, for: preset)
                    }
                }
            } label: {
                Text("Use \(browser.name) for a while")
            }
            .accessibilityLabel("Use \(browser.name) for a while")
            .accessibilityIdentifier("borrow-browser-\(browser.name)")
        }

        if store.isSmartRoutingConfigured {
            Toggle(
                "Let Shortcuts switch browsers",
                isOn: Binding(
                    get: { store.allowsAutomationLeases },
                    set: { store.setAutomationLeasesAllowed($0) }
                )
            )
            .accessibilityIdentifier("allow-automation-leases")
            .accessibilityHint(focusHelp)
            .help(focusHelp)
            .disabled(store.isSwitching)

            if let fallback {
                Button("Stop. Make \(fallback.name) the usual browser.") {
                    Task { await store.disableSmartRouting() }
                }
                .disabled(store.isSwitching)
                .accessibilityIdentifier("disable-smart-routing")
            }
        } else if let fallback {
            Button("Send links through Linkpick. Otherwise use \(fallback.name).") {
                Task { await store.enableSmartRouting() }
            }
            .disabled(store.isSwitching)
            .accessibilityIdentifier("enable-smart-routing")
        }

        if let message = store.message {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var focusHelp: String {
        "Shortcuts can switch browsers while Linkpick is sending links. Linkpick does not read Focus."
    }

    private var modeBadge: String {
        switch store.routingState {
        case .direct: "Usual"
        case .enabling, .disabling: "Waiting"
        case .smartActive: "On"
        case .smartSuspended: "Paused"
        case .degraded: "Check"
        }
    }

    private var modeColor: Color {
        switch store.routingState {
        case .direct: .secondary
        case .enabling, .disabling: .blue
        case .smartActive: .green
        case .smartSuspended, .degraded: .orange
        }
    }
}

private struct BrowserLeaseRows: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lease = store.activeBrowserLease {
                Label(
                    "Using \(store.displayName(for: lease.browser))",
                    systemImage: "clock.arrow.trianglehead.2.counterclockwise.rotate.90"
                )
                .font(.headline)
                .accessibilityIdentifier("active-lease-title")

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(store.activeLeaseRemainingText ?? "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            "active-lease-remaining"
                        )
                }

                Button(
                    "Stop",
                    systemImage: "stop.circle"
                ) {
                    store.endBrowserLease()
                }
                .accessibilityLabel("Stop")
                .accessibilityIdentifier("end-browser-lease")
            } else {
                Text(
                    "The temporary browser ended. Rules are in use again."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if store.canUndoLease {
                Button(
                    "Undo",
                    systemImage: "arrow.uturn.backward"
                ) {
                    store.undoBrowserLeaseChange()
                }
                .accessibilityLabel("Undo")
                .accessibilityIdentifier("undo-browser-lease")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HandlerTransactionControls: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.hasSplitHandlers {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        "HTTP and HTTPS open in different browsers",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.orange)

                    if let message = store.splitHandlerMessage {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("split-handler-warning")
                    }

                    if !store.isSmartRoutingConfigured,
                       let browser = store.selectedBrowserForRepair {
                        Button("Use \(browser.name) for both HTTP and HTTPS") {
                            Task { await store.repairSelectedHandlers() }
                        }
                        .disabled(store.isSwitching)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if store.canUndo {
                Button("Undo last browser change", systemImage: "arrow.uturn.backward") {
                    Task { await store.undoLastBrowserChange() }
                }
                .disabled(store.isSwitching)
                .accessibilityIdentifier("undo-browser-change")
            }
        }
    }
}
