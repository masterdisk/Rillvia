import SwiftUI

struct BrowserSidebar: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        List {
            Section("Routing") {
                WorkspaceNavigationRow(
                    destination: .direct,
                    title: "Direct switcher",
                    systemImage: "arrow.up.right.square"
                )
                WorkspaceNavigationRow(
                    destination: .airlock,
                    title: "Link Airlock",
                    systemImage: "checkmark.shield"
                )
                WorkspaceNavigationRow(
                    destination: .rules,
                    title: "Rules",
                    systemImage: "arrow.triangle.branch"
                )
                WorkspaceNavigationRow(
                    destination: .profiles,
                    title: "Profiles",
                    systemImage: "person.2"
                )
            }

            Section {
                ForEach(store.browsers) { browser in
                    BrowserSidebarRow(browser: browser)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectBrowser(browser.id)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        store.selectBrowser(browser.id)
                    }
                    .listRowBackground(
                        store.workspaceDestination == .direct
                            && store.selectedID == browser.id
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear
                    )
                }
            } header: {
                Text("Browsers")
                    .onTapGesture {
                        store.tapTitle()
                    }
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
                .interpolation(.high)
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
                            ? "Smart Routing fallback"
                            : "Current default"
                    )
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel(browser.name)
        .accessibilityValue(
            isDefault
                ? "\(browser.version), \(store.isSmartRoutingConfigured ? "Smart Routing fallback" : "current default")"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose where links open")
                        .font(.system(size: 30, weight: .semibold))
                        .accessibilityIdentifier("workspace-title")
                    Text(
                        store.isSmartRoutingConfigured
                            ? "Select a browser to use as the external fallback. BrowserChange never opens links inside the app."
                            : "Select a browser, then make it the default for web links on this Mac."
                    )
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                RoutingModeCard()

                if store.activeBrowserLease != nil
                    || store.canUndoLease {
                    BrowserLeaseCard()
                }

                HandlerTransactionControls()

                if let browser = store.browsers.first(where: { $0.id == store.selectedID }) {
                    BrowserLens(browser: browser)
                        .id(browser.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                Divider()

                RoutingSummaryView()
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: store.selectedID)
    }
}

private struct BrowserLeaseCard: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lease = store.activeBrowserLease {
                Label(
                    "Borrowing \(store.displayName(for: lease.browser))",
                    systemImage: "clock.arrow.trianglehead.2.counterclockwise.rotate.90"
                )
                .font(.headline)
                .accessibilityIdentifier("active-lease-title")

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(store.activeLeaseRemainingText ?? "")
                        .font(.title3.monospacedDigit())
                        .accessibilityIdentifier(
                            "active-lease-remaining"
                        )
                }

                Text(
                    "This temporary override leaves your permanent fallback and domain rules unchanged."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button(
                    "End Lease",
                    systemImage: "stop.circle"
                ) {
                    store.endBrowserLease()
                }
                .accessibilityLabel("End browser lease")
                .accessibilityIdentifier("end-browser-lease")
            } else {
                Text(
                    "The temporary browser override has ended. Your permanent fallback and domain rules are active."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if store.canUndoLease {
                Button(
                    "Undo lease change",
                    systemImage: "arrow.uturn.backward"
                ) {
                    store.undoBrowserLeaseChange()
                }
                .accessibilityLabel("Undo browser lease change")
                .accessibilityIdentifier("undo-browser-lease")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.indigo.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.indigo.opacity(0.2))
        }
    }
}

private struct RoutingModeCard: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let fallback = store.smartFallbackBrowser
            ?? store.switchable.first {
                $0.id == store.defaultBundleID
            }

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: modeSymbol)
                        .accessibilityHidden(true)
                    Text(store.routingModeTitle)
                        .accessibilityIdentifier("routing-mode-title")
                }
                .font(.headline)

                Spacer()

                Text(modeBadge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(modeColor)
            }

            Text(store.routingModeDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("routing-mode-detail")

            if store.isSmartRoutingConfigured {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        "Allow Shortcuts to start leases",
                        isOn: Binding(
                            get: {
                                store.allowsAutomationLeases
                            },
                            set: {
                                store.setAutomationLeasesAllowed($0)
                            }
                        )
                    )
                    .accessibilityIdentifier(
                        "allow-automation-leases"
                    )
                    .disabled(store.isSwitching)

                    Text(
                        "Off by default. This permission never turns on Smart Routing; it only lets Shortcuts start a temporary lease while Smart Routing is verified active."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(
                        "For a Work Focus automation, use Set Routing Profile or Start Browser Lease when Focus turns on, then End Browser Lease or Restore Previous Browser when it turns off. BrowserChange does not read or infer Focus state."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        "focus-automation-guidance"
                    )
                }

                if let fallback {
                    Button(
                        "Turn off Smart Routing and make \(fallback.name) the Direct default"
                    ) {
                        Task { await store.disableSmartRouting() }
                    }
                    .disabled(store.isSwitching)
                    .accessibilityIdentifier("disable-smart-routing")
                }
            } else if let fallback {
                Button(
                    "Turn on Smart Routing with \(fallback.name)"
                ) {
                    Task { await store.enableSmartRouting() }
                }
                .buttonStyle(.glassProminent)
                .disabled(store.isSwitching)
                .accessibilityIdentifier("enable-smart-routing")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(modeColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(modeColor.opacity(0.2))
        }
    }

    private var modeSymbol: String {
        switch store.routingState {
        case .direct:
            "arrow.up.right.square"
        case .enabling, .disabling:
            "arrow.triangle.2.circlepath"
        case .smartActive:
            "point.3.connected.trianglepath.dotted"
        case .smartSuspended:
            "pause.circle.fill"
        case .degraded:
            "exclamationmark.triangle.fill"
        }
    }

    private var modeBadge: String {
        switch store.routingState {
        case .direct:
            "DIRECT"
        case .enabling:
            "ENABLING"
        case .smartActive:
            "ACTIVE"
        case .smartSuspended:
            "SUSPENDED"
        case .disabling:
            "DISABLING"
        case .degraded:
            "DEGRADED"
        }
    }

    private var modeColor: Color {
        switch store.routingState {
        case .direct:
            .secondary
        case .enabling, .disabling:
            .blue
        case .smartActive:
            .green
        case .smartSuspended, .degraded:
            .orange
        }
    }
}

private struct HandlerTransactionControls: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.hasSplitHandlers {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        "HTTP and HTTPS handlers are split",
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
                        Button("Repair handlers with \(browser.name)") {
                            Task { await store.repairSelectedHandlers() }
                        }
                        .disabled(store.isSwitching)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.orange.opacity(0.24))
                }
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

private struct BrowserLens: View {
    @Environment(BrowserStore.self) private var store
    var browser: InstalledBrowser

    var body: some View {
        let isDefault = browser.id == store.defaultBundleID

        HStack(spacing: 30) {
            Image(nsImage: store.icon(for: browser))
                .resizable()
                .interpolation(.high)
                .frame(width: 82, height: 82)
                .padding(28)
                .glassEffect(
                    .regular.tint(
                        isDefault
                            ? Color.green.opacity(0.16)
                            : Color.accentColor.opacity(0.12)
                    ),
                    in: Circle()
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(browser.name)
                        .font(.system(size: 27, weight: .semibold))
                        .lineLimit(2)
                    Text("Version \(browser.version)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if isDefault {
                    Label(
                        store.isSmartRoutingConfigured
                            ? "Smart Routing fallback"
                            : "Current default",
                        systemImage: "checkmark.circle.fill"
                    )
                        .font(.body.weight(.medium))
                        .foregroundStyle(.green)
                    Text(
                        store.isSmartRoutingConfigured
                            ? "BrowserChange forwards unmatched web links here."
                            : "Web links open here."
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if browser.isImaginary {
                    Text("Lynx lives in a terminal. This Mac wants a window.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if store.isSmartRoutingConfigured {
                    Text(
                        "\(store.defaultBrowserName) is the current Smart Routing fallback."
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button(
                        "Use \(browser.name) as Smart Routing fallback"
                    ) {
                        Task { await store.makeDefault(browser) }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(store.isSwitching)
                } else {
                    Text(
                        store.hasSplitHandlers
                            ? "HTTP and HTTPS links currently open in different browsers."
                            : "Links currently open in \(store.defaultBrowserName)."
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button("Make \(browser.name) the default") {
                        Task { await store.makeDefault(browser) }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(store.isSwitching)
                    .keyboardShortcut(.defaultAction)
                }

                if store.isSmartRoutingActive && !browser.isImaginary {
                    Menu {
                        ForEach(BrowserLeasePreset.allCases) { preset in
                            Button(preset.title) {
                                store.borrowBrowser(
                                    browser,
                                    for: preset
                                )
                            }
                        }
                    } label: {
                        Label(
                            "Borrow \(browser.name)",
                            systemImage: "clock.badge.checkmark"
                        )
                    }
                    .controlSize(.large)
                    .accessibilityLabel("Borrow \(browser.name)")
                    .accessibilityIdentifier(
                        "borrow-browser-\(browser.name)"
                    )
                }

                Text(store.message ?? " ")
                    .font(.callout)
                    .foregroundStyle(store.message == nil ? Color.clear : Color.secondary)
                    .frame(minHeight: 18)
                    .accessibilityHidden(store.message == nil)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }
}
