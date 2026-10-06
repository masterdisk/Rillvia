import AppKit
import SwiftUI

struct MenuBarLabel: View {
    var image: NSImage
    var name: String

    var body: some View {
        Image(nsImage: menuImage(image))
            .accessibilityLabel("Linkpick, \(name)")
    }

    private func menuImage(_ source: NSImage) -> NSImage {
        let copy = (source.copy() as? NSImage) ?? source
        copy.size = NSSize(width: 18, height: 18)
        copy.isTemplate = false
        return copy
    }
}

struct MenuPanel: View {
    var delegate: AppDelegate
    @Environment(BrowserStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let fallback = store.smartFallbackBrowser
            ?? store.switchable.first {
                $0.id == store.defaultBundleID
            }

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.routingModeTitle)
                    .font(.headline)
                    .accessibilityIdentifier("menu-routing-mode-title")
                Text(store.routingModeDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            if store.hasSplitHandlers {
                Text("HTTP and HTTPS open in different browsers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                if let message = store.splitHandlerMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                }
                if !store.isSmartRoutingConfigured,
                   let browser = store.selectedBrowserForRepair {
                    MenuRow(title: "Use \(browser.name) for both") {
                        Task { await store.repairSelectedHandlers() }
                    }
                    .disabled(store.isSwitching)
                }
            }

            if store.switchable.count > 7 {
                ScrollView { rows }
                    .frame(height: 320)
            } else {
                rows
            }

            if store.activeBrowserLease != nil || store.canUndoLease {
                sectionRule
                MenuLeaseControls()
            }

            if store.isSmartRoutingActive {
                sectionRule
                MenuBorrowControls()
            }

            if store.hasClipboardWebURL {
                MenuRow(
                    title: "Open clipboard link",
                    identifier: "menu-open-clipboard-link"
                ) {
                    guard store.stageClipboardURL() else { return }
                    presentMainWindow()
                }
            }

            if store.canUndo {
                MenuRow(
                    title: "Undo last change",
                    identifier: "menu-undo-browser-change"
                ) {
                    Task { await store.undoLastBrowserChange() }
                }
                .disabled(store.isSwitching)
            }

            if let message = store.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }

            sectionRule

            if store.isSmartRoutingConfigured, let fallback {
                MenuRow(title: "Use \(fallback.name) for every link") {
                    Task { await store.disableSmartRouting() }
                }
                .disabled(store.isSwitching)
            } else if let fallback {
                MenuRow(title: "Send links through Linkpick") {
                    Task { await store.enableSmartRouting() }
                }
                .disabled(store.isSwitching)
            }

            MenuRow(title: "Open Linkpick", identifier: "menu-open-app") {
                presentMainWindow()
            }
            MenuRow(title: "Quit Linkpick", identifier: "menu-quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(.bottom, 6)
        .frame(width: 248)
    }

    private var sectionRule: some View {
        Divider()
            .padding(.vertical, 4)
    }

    private func presentMainWindow() {
        delegate.userWantsMainWindow()
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        dismiss()
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(store.switchable) { browser in
                BrowserMenuRow(browser: browser)
            }
        }
    }
}

private struct MenuBorrowControls: View {
    @Environment(BrowserStore.self) private var store
    @State private var pickingBrowser = false
    @State private var chosen: InstalledBrowser?

    var body: some View {
        if let chosen {
            ForEach(BrowserLeasePreset.allCases) { preset in
                MenuRow(
                    title: preset.actionTitle(browserName: chosen.name),
                    identifier: preset == .fifteenMinutes
                        ? "menu-borrow-confirm"
                        : nil
                ) {
                    store.borrowBrowser(chosen, for: preset)
                    self.chosen = nil
                    pickingBrowser = false
                }
            }
        } else if pickingBrowser {
            ForEach(store.borrowableBrowsers) { browser in
                MenuRow(
                    title: browser.name,
                    identifier: "menu-borrow-choice-\(browser.name)"
                ) {
                    chosen = browser
                }
            }
        } else {
            MenuRow(title: "For a while", identifier: "menu-borrow-browser") {
                pickingBrowser = true
            }
        }
    }
}

private struct MenuLeaseControls: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        if let lease = store.activeBrowserLease {
            HStack {
                Text("Using \(store.displayName(for: lease.browser))")
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("menu-active-lease-title")
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(store.activeLeaseRemainingText ?? "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("menu-active-lease-remaining")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            MenuRow(title: "Stop", identifier: "menu-end-browser-lease") {
                store.endBrowserLease()
            }
            .accessibilityLabel("Stop")
        }

        if store.canUndoLease {
            MenuRow(title: "Undo", identifier: "menu-undo-browser-lease") {
                store.undoBrowserLeaseChange()
            }
            .accessibilityLabel("Undo")
        }
    }
}

private struct MenuRow: View {
    var title: String
    var identifier: String?
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .background(hovering ? Color.primary.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .modifier(MenuRowIdentifier(identifier: identifier))
    }
}

private struct MenuRowIdentifier: ViewModifier {
    var identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
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
                    .interpolation(.medium)
                    .frame(width: 22, height: 22)
                Text(browser.name)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isDefault {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .accessibilityLabel(
                            store.isSmartRoutingConfigured
                                ? "Browser for sites with no rule"
                                : "Usual browser"
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
                ? "Browser for sites with no rule"
                : ""
        )
        .accessibilityAddTraits(isDefault ? .isSelected : [])
    }
}
