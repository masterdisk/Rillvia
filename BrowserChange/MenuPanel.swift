import AppKit
import SwiftUI

struct MenuBarLabel: View {
    var image: NSImage?
    var name: String
    var body: some View {
        Group {
            if let image { Image(nsImage: menuImage(image)) }
            else { Image(systemName: "arrow.triangle.branch") }
        }.accessibilityLabel(name)
    }
    private func menuImage(_ source: NSImage) -> NSImage {
        let copy = (source.copy() as? NSImage) ?? source
        copy.size = NSSize(width: 18, height: 18)
        copy.isTemplate = true
        return copy
    }
}

struct MenuPanel: View {
    private let panelWidth: CGFloat = 400
    private let contentInset: CGFloat = 16
    var delegate: AppDelegate
    @Environment(BrowserStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance", store: AppPreferences.defaults) private var appearance = "system"
    @State private var browserID = ""
    @State private var duration: BrowserLeasePreset = .fifteenMinutes
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image("AppLogo").resizable().frame(width: 35, height: 35).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppBrand.name).font(.system(size: 20, weight: .semibold))
                    RoutingStatus().accessibilityIdentifier("menu-routing-mode-title")
                }
                Spacer()
            }.frame(width: panelWidth - 40, alignment: .leading).padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text(store.isSmartRoutingActive ? "Other links" : "Default browser").foregroundStyle(.secondary).frame(width: 118, alignment: .leading)
                            BrowserIcon(browser: store.isSmartRoutingActive ? store.smartFallbackBrowser : store.currentMacOSBrowser, size: 22)
                            Text(store.isSmartRoutingActive ? store.smartFallbackBrowser?.name ?? "Choose a browser" : store.currentMacOSBrowserName)
                                .fontWeight(.medium).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("menu-other-links-browser")
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 12) {
                            Text("Active rule set").foregroundStyle(.secondary).frame(width: 118, alignment: .leading)
                            Image(systemName: "square.3.layers.3d").foregroundStyle(.secondary).frame(width: 22)
                            Text(store.routingConfiguration.profiles.first { $0.id == store.routingConfiguration.activeProfileID }?.name ?? "Shared rules only").fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }.font(.callout)

                    Divider()
                    ActiveBrowserNotice()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Use temporarily").font(.system(size: 20, weight: .semibold))
                        Text("Send links to one browser for a while.").font(.callout).foregroundStyle(.secondary)
                    }
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(store.externalBrowsers) { browser in
                                Button { browserID = browser.id } label: {
                                    HStack(spacing: 10) {
                                        BrowserIcon(browser: browser, size: 24)
                                        Text(browser.name).fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 8)
                                        Image(systemName: browserID == browser.id ? "checkmark.circle.fill" : "circle").foregroundStyle(browserID == browser.id ? Color.accentColor : Color.secondary)
                                    }.padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                        .background(browserID == browser.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).accessibilityIdentifier("menu-choice-\(browser.id)")
                            }
                        }
                    }.frame(height: min(CGFloat(store.externalBrowsers.count) * 38, 152))
                    HStack(spacing: 10) {
                        Text("For").foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
                        Picker("Temporary duration", selection: $duration) {
                            Text("15 min").tag(BrowserLeasePreset.fifteenMinutes)
                            Text("30 min").tag(BrowserLeasePreset.thirtyMinutes)
                            Text("60 min").tag(BrowserLeasePreset.sixtyMinutes)
                            Text("Until ended").tag(BrowserLeasePreset.untilEnded)
                        }.labelsHidden().pickerStyle(.segmented)
                            .controlSize(.small)
                            .frame(width: panelWidth - contentInset * 2 - 32)
                            .accessibilityIdentifier("menu-duration")
                    }
                    Button {
                        if let chosen { _ = store.borrowBrowser(chosen, for: duration) }
                    } label: { Text(duration.actionTitle(browserName: chosen?.name ?? "a browser")).fixedSize(horizontal: false, vertical: true).frame(minWidth: 0, maxWidth: .infinity, minHeight: 24) }
                    .buttonStyle(.glassProminent).controlSize(.large)
                        .disabled(chosen == nil || !store.isSmartRoutingActive)
                        .accessibilityIdentifier("menu-start-temporary-browser")
                    Text(store.isSmartRoutingActive ? "Your rules resume when it ends." : "Turn on rules in Overview first.").font(.callout).foregroundStyle(.secondary)
                    if store.hasClipboardWebURL {
                        Button("Preview clipboard link", systemImage: "doc.on.clipboard") {
                            guard store.stageClipboardURL() else { return }
                            store.workspace.previewInput = store.airlockResult.items.map(\.originalText).joined(separator: "\n")
                            store.workspace.markPreview(input: store.workspace.previewInput, revision: store.revision)
                            presentMainWindow()
                        }.buttonStyle(.link).accessibilityIdentifier("menu-open-clipboard-link")
                    }
                    StoreNotice()
                }
                // Scroll content must keep the panel's width when native controls update their intrinsic size.
                .frame(width: panelWidth - contentInset * 2, alignment: .leading)
                .padding(contentInset)
            }.frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 12) {
                Button("Open Rillvia", systemImage: "macwindow") { presentMainWindow() }.buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("menu-open-app")
                Spacer(minLength: 0)
                Menu {
                    Button("Keyboard shortcuts") { presentMainWindow(); store.workspace.showKeyboardShortcuts = true }
                    Button("Diagnostics") { presentMainWindow(); store.openDiagnostics() }
                    Divider()
                    Button("Quit Rillvia") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More options")
            }.frame(width: panelWidth - contentInset * 2, alignment: .leading).padding(contentInset)
        }.font(.system(size: 14)).buttonBorderShape(.roundedRectangle)
            .frame(width: panelWidth, height: 560, alignment: .topLeading)
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .onAppear {
                browserID = store.activeLeaseBrowser?.id ?? store.externalBrowsers.first { $0.reference != store.smartFallbackBrowser?.reference }?.id ?? store.externalBrowsers.first?.id ?? ""
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-design-fixture") { browserID = "com.google.Chrome" }
                #endif
            }
    }
    private var chosen: InstalledBrowser? { store.externalBrowsers.first { $0.id == browserID } }
    private func presentMainWindow() {
        delegate.userWantsMainWindow()
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        dismiss()
    }
}
