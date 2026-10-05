import SwiftUI

struct BrowserSidebar: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedID) {
            Section {
                ForEach(store.browsers) { browser in
                    BrowserSidebarRow(browser: browser)
                        .tag(browser.id)
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
                    .accessibilityLabel("Current default")
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel(browser.name)
        .accessibilityValue(isDefault ? "\(browser.version), current default" : browser.version)
    }
}

struct BrowserWorkspace: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose where links open")
                        .font(.system(size: 30, weight: .semibold))
                        .accessibilityIdentifier("workspace-title")
                    Text("Select a browser, then make it the default for web links on this Mac.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HandlerTransactionControls()

                if let browser = store.browsers.first(where: { $0.id == store.selectedID }) {
                    BrowserLens(browser: browser)
                        .id(browser.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                Divider()

                FutureFeaturesView()
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

                    if let browser = store.selectedBrowserForRepair {
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
                    Label("Current default", systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.green)
                    Text("Web links open here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if browser.isImaginary {
                    Text("Lynx lives in a terminal. This Mac wants a window.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
