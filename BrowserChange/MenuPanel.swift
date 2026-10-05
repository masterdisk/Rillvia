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
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.defaultBrowserName)
                    .font(.headline)
                Text("Choose the one links open in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                    if let browser = store.selectedBrowserForRepair {
                        Button("Repair handlers with \(browser.name)") {
                            Task { await store.repairSelectedHandlers() }
                        }
                        .disabled(store.isSwitching)
                    }
                }
                .padding(8)
                .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
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
                        .accessibilityLabel("Default")
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
        .accessibilityAddTraits(isDefault ? .isSelected : [])
    }
}
