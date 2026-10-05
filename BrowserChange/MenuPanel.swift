import AppKit
import SwiftUI

struct MenuBarLabel: View {
    var image: NSImage
    var name: String

    var body: some View {
        Image(nsImage: menuImage(image))
            .accessibilityLabel("BrowserChange, \(name)")
    }

    private func menuImage(_ source: NSImage) -> NSImage {
        let copy = (source.copy() as? NSImage) ?? source
        copy.size = NSSize(width: 18, height: 18)
        copy.isTemplate = false
        return copy
    }
}

struct MenuPanel: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let fallback = store.smartFallbackBrowser
            ?? store.switchable.first {
                $0.id == store.defaultBundleID
            }

        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.routingModeTitle)
                    .font(.headline)
                    .accessibilityIdentifier("menu-routing-mode-title")
                Text(
                    store.isSmartRoutingConfigured
                        ? "\(store.defaultBrowserName) is the external fallback."
                        : "\(store.defaultBrowserName) is the Direct default."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.routingModeDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            if store.hasSplitHandlers {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        "HTTP and HTTPS handlers are split",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)

                    if let message = store.splitHandlerMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !store.isSmartRoutingConfigured,
                       let browser = store.selectedBrowserForRepair {
                        Button("Repair handlers with \(browser.name)") {
                            Task { await store.repairSelectedHandlers() }
                        }
                        .disabled(store.isSwitching)
                    }
                }
                .padding(8)
                .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            }

            if store.isSmartRoutingConfigured {
                if let fallback {
                    Button {
                        Task { await store.disableSmartRouting() }
                    } label: {
                        Label(
                            "Turn off Smart Routing and make \(fallback.name) the Direct default",
                            systemImage: "arrow.up.right.square"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(store.isSwitching)
                }
            } else if let fallback {
                Button {
                    Task { await store.enableSmartRouting() }
                } label: {
                    Label(
                        "Turn on Smart Routing with \(fallback.name)",
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(store.isSwitching)
            }

            if store.activeBrowserLease != nil || store.canUndoLease {
                MenuLeaseControls()
            }

            if store.isSmartRoutingActive {
                Menu {
                    ForEach(store.borrowableBrowsers) { browser in
                        ForEach(BrowserLeasePreset.allCases) { preset in
                            Button(
                                preset.actionTitle(
                                    browserName: browser.name
                                )
                            ) {
                                store.borrowBrowser(
                                    browser,
                                    for: preset
                                )
                            }
                        }
                        if browser.id
                            != store.borrowableBrowsers.last?.id {
                            Divider()
                        }
                    }
                } label: {
                    Label(
                        "Borrow a browser",
                        systemImage: "clock.badge.checkmark"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Borrow a browser temporarily")
                .accessibilityIdentifier("menu-borrow-browser")
            }

            if store.hasClipboardWebURL {
                Button {
                    guard store.stageClipboardURL() else { return }
                    openWindow(id: "main")
                    NSApp.activate()
                    dismiss()
                } label: {
                    Label(
                        "Open Clipboard Link…",
                        systemImage: "checkmark.shield"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("menu-open-clipboard-link")
            }

            if store.switchable.count > 7 {
                ScrollView {
                    rows
                }
                .frame(height: 380)
            } else {
                rows
            }

            if store.canUndo {
                Button {
                    Task { await store.undoLastBrowserChange() }
                } label: {
                    Label(
                        "Undo last browser change",
                        systemImage: "arrow.uturn.backward"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(store.isSwitching)
                .accessibilityIdentifier("menu-undo-browser-change")
            }

            if let message = store.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }

            Button {
                openWindow(id: "main")
                NSApp.activate()
                dismiss()
            } label: {
                Text("Open BrowserChange")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .padding(12)
        .frame(width: 300)
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(store.switchable) { browser in
                BrowserMenuRow(browser: browser)
            }
        }
    }
}

private struct MenuLeaseControls: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let lease = store.activeBrowserLease {
                Text(
                    "Borrowing \(store.displayName(for: lease.browser))"
                )
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("menu-active-lease-title")

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(store.activeLeaseRemainingText ?? "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            "menu-active-lease-remaining"
                        )
                }

                Text("Fallback and rules stay unchanged.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button("End Lease", systemImage: "stop.circle") {
                    store.endBrowserLease()
                }
                .accessibilityLabel("End browser lease")
                .accessibilityIdentifier("menu-end-browser-lease")
            }

            if store.canUndoLease {
                Button(
                    "Undo lease change",
                    systemImage: "arrow.uturn.backward"
                ) {
                    store.undoBrowserLeaseChange()
                }
                .accessibilityLabel("Undo browser lease change")
                .accessibilityIdentifier("menu-undo-browser-lease")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.indigo.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

private struct BrowserMenuRow: View {
    @Environment(BrowserStore.self) private var store
    var browser: InstalledBrowser
    @State private var hovering = false

    var body: some View {
        let isDefault = browser.id == store.defaultBundleID
        Button {
            if NSEvent.modifierFlags.contains(.option) {
                store.copyIdentity(of: browser)
            } else {
                Task { await store.makeDefault(browser) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: store.icon(for: browser))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                Text(browser.name)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isDefault {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .accessibilityLabel(
                            store.isSmartRoutingConfigured
                                ? "Smart Routing fallback"
                                : "Default"
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .disabled(store.isSwitching)
        .onHover { hovering = $0 }
        .accessibilityLabel(browser.name)
        .accessibilityValue(
            isDefault && store.isSmartRoutingConfigured
                ? "Smart Routing fallback"
                : ""
        )
        .accessibilityAddTraits(isDefault ? .isSelected : [])
    }
}
