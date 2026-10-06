import SwiftUI

struct BrowsersView: View {
    @Environment(BrowserStore.self) private var store
    @FocusState private var searchFocused: Bool
    private var listedBrowsers: [InstalledBrowser] { store.externalBrowsers + store.browsers.filter(\.isImaginary) }
    private var selected: InstalledBrowser? { listedBrowsers.first { $0.id == store.selectedID } ?? store.externalBrowsers.first }
    var body: some View {
        @Bindable var workspace = store.workspace
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 17) {
                PageHeading(title: "Browsers", subtitle: "\(store.externalBrowsers.count) installed", identifier: "browsers-title")
                TextField("Search browsers", text: $workspace.browserSearch).textFieldStyle(.roundedBorder).focused($searchFocused).accessibilityIdentifier("browser-search")
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(listedBrowsers.filter { workspace.browserSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(workspace.browserSearch) }) { browser in
                            BrowserListRow(browser: browser, isSelected: browser.id == selected?.id)
                        }
                    }
                }
            }.padding(20).frame(width: 255)
            Divider()
            if let browser = selected {
                if browser.isImaginary {
                    VStack(alignment: .leading, spacing: 20) {
                        BrowserIcon(browser: browser, size: 52)
                        PageHeading(title: "Lynx", subtitle: "Text only. A little nod to the terminal.", identifier: "lynx-title")
                        Button("Back to browsers") { if let first = store.externalBrowsers.first { store.selectBrowser(first.id) } }.buttonStyle(.glass)
                        StoreNotice()
                        Spacer()
                    }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
                } else { BrowserDetailsView(browser: browser) }
            } else { ContentUnavailableView("No matching browsers", systemImage: "safari", description: Text("Try another name or refresh the browser list.")) }
        }
        .onChange(of: workspace.focusRequest) { _, _ in if workspace.focus == .search { searchFocused = true } }
    }
}

private struct BrowserListRow: View {
    @Environment(BrowserStore.self) private var store
    let browser: InstalledBrowser
    let isSelected: Bool
    var body: some View {
        Button { store.selectBrowser(browser.id) } label: {
            HStack(spacing: 12) {
                BrowserIcon(browser: browser, size: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text(browser.name).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    if store.isSmartRoutingConfigured && browser.reference == store.smartFallbackBrowser?.reference {
                        Text("Other links").font(.caption).foregroundStyle(.secondary)
                    } else if !store.isSmartRoutingConfigured && browser.id == store.defaultBundleID {
                        Text("Default browser").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityIdentifier("browser-row-\(browser.name)")
    }
}

private struct BrowserDetailsView: View {
    @Environment(BrowserStore.self) private var store
    let browser: InstalledBrowser
    var body: some View {
                ScrollView {
                    VStack(alignment: .leading, spacing: 23) {
                        HStack(spacing: 16) {
                            BrowserIcon(browser: browser, size: 56)
                            PageHeading(title: browser.name, subtitle: "Version \(browser.version)", identifier: "browser-detail-title")
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Links").font(.headline)
                            Text(store.isSmartRoutingConfigured ? "Choose this browser for links without a matching rule." : "Choose the macOS default for HTTP and HTTPS links.")
                                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button(store.isSmartRoutingConfigured ? "Use for other links" : "Make \(browser.name) default") { Task { await store.makeDefault(browser) } }
                                .buttonStyle(.glassProminent).controlSize(.large).disabled(store.isSwitching || isCurrent(browser))
                                .accessibilityIdentifier("use-selected-browser")
                            Button("Use a browser temporarily") { store.workspace.showTemporaryBrowser = true }
                                .buttonStyle(.glass).controlSize(.large).disabled(!store.isSmartRoutingActive)
                        }
                        if store.hasSplitHandlers, let splitMessage = store.splitHandlerMessage {
                            Text(splitMessage).foregroundStyle(.orange).accessibilityIdentifier("split-handler-warning")
                            Button("Use \(browser.name) for both HTTP and HTTPS") { Task { await store.repairSelectedHandlers() } }.disabled(store.isSwitching)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 13) {
                            Text("Profiles").font(.headline)
                            let profiles = store.browserProfiles(for: browser.id)
                            if profiles.isEmpty {
                                Text("No profiles available to choose. Links use the browser’s default profile.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(profiles) { profile in Label(profile.name, systemImage: "person.crop.circle").fixedSize(horizontal: false, vertical: true) }
                                Text("Choose a profile in a rule or when opening a previewed link.").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        if store.supportsPrivateWindow(browser.id) {
                            Divider()
                            Label("Private windows supported", systemImage: "eye.slash").font(.headline)
                            Text("Preview a link, then choose this browser and turn on “Open this link in a private window.”").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if store.canUndo {
                            Button("Undo last browser change") { Task { await store.undoLastBrowserChange() } }.disabled(store.isSwitching)
                        }
                        StoreNotice()
                    }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
                }
    }
    private func isCurrent(_ browser: InstalledBrowser) -> Bool {
        store.isSmartRoutingConfigured ? browser.reference == store.smartFallbackBrowser?.reference : !store.hasSplitHandlers && browser.id == store.defaultBundleID
    }
}
