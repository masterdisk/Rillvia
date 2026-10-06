import AppKit
import SwiftUI

enum AppBrand {
    static let name = "Rillvia"
    static var menuImage: NSImage? {
        guard let image = NSImage(named: "BrandMark")?.copy() as? NSImage else { return nil }
        image.isTemplate = true
        return image
    }
}

struct BrowserIcon: View {
    @Environment(BrowserStore.self) private var store
    let browser: InstalledBrowser?
    var size: CGFloat = 24
    var body: some View {
        Group {
            if let browser { Image(nsImage: store.icon(for: browser)).resizable().interpolation(.high) }
            else { Image(systemName: "globe").resizable().scaledToFit().foregroundStyle(.secondary).padding(2) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PageHeading: View {
    let title: String
    var subtitle: String? = nil
    var identifier = "workspace-title"
    var size: CGFloat = 28
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: size, weight: .bold)).accessibilityIdentifier(identifier)
            if let subtitle { Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

struct FieldCaption<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .medium))
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShortcutHint: View {
    let keys: String
    var body: some View {
        Text(keys).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            .fixedSize().accessibilityHidden(true)
    }
}

struct RoutingStatus: View {
    @Environment(BrowserStore.self) private var store
    var body: some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: store.isSmartRoutingActive ? "circle.fill" : "pause.circle")
                .font(.system(size: store.isSmartRoutingActive ? 8 : 13))
                .foregroundStyle(store.isSmartRoutingActive ? Color.green : Color.secondary)
        }
            .font(.system(size: 13, weight: .medium))
            .accessibilityIdentifier("routing-mode-title")
    }
    private var title: String {
        switch store.routingState {
        case .smartActive: "Rules are on"
        case .smartSuspended: "Rules are paused"
        case .enabling, .disabling: "Updating rules"
        case .degraded: "Links need attention"
        case .direct: "Rules are off"
        }
    }
}

struct StoreNotice: View {
    @Environment(BrowserStore.self) private var store
    var body: some View {
        if let message = store.message {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(message).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if store.canUndoConfiguration {
                    Button("Undo") { store.workspace.request { _ = store.undoConfigurationChange() } }
                        .accessibilityIdentifier("undo-configuration")
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("store-notice")
        }
    }
}

struct TemporaryBrowserSheet: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var initialBrowserID: String? = nil
    @State private var browserID = ""
    @State private var duration: BrowserLeasePreset = .fifteenMinutes
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeading(title: "Use a browser temporarily", subtitle: "All links use this browser until the timer ends. Your rules resume afterward.")
            TemporaryBrowserForm(browserID: $browserID, duration: $duration)
            StoreNotice()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(duration.actionTitle(browserName: chosen?.name ?? "a browser")) {
                    if let chosen, store.borrowBrowser(chosen, for: duration) { dismiss() }
                }
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                .disabled(chosen == nil || !store.isSmartRoutingActive)
                .accessibilityIdentifier("start-temporary-browser")
            }
        }.padding(28).frame(width: 510)
        .onAppear { browserID = initialBrowserID ?? store.smartFallbackBrowser?.id ?? store.externalBrowsers.first?.id ?? "" }
    }
    private var chosen: InstalledBrowser? { store.externalBrowsers.first { $0.id == browserID } }
}

struct TemporaryBrowserForm: View {
    @Environment(BrowserStore.self) private var store
    @Binding var browserID: String
    @Binding var duration: BrowserLeasePreset
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldCaption(title: "Browser") {
                Picker("Temporary browser", selection: $browserID) {
                    ForEach(store.externalBrowsers) { browser in Text(browser.name).tag(browser.id) }
                }.labelsHidden().controlSize(.large).frame(maxWidth: .infinity).accessibilityIdentifier("temporary-browser-picker")
            }
            FieldCaption(title: "For how long?") {
                Picker("Duration", selection: $duration) {
                    ForEach(BrowserLeasePreset.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().controlSize(.large).frame(maxWidth: .infinity).accessibilityIdentifier("temporary-duration-picker")
            }
            if !store.isSmartRoutingActive {
                Text("Turn on rules in Overview to use a temporary browser.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct ActiveBrowserNotice: View {
    @Environment(BrowserStore.self) private var store
    var body: some View {
        if let browser = store.activeLeaseBrowser {
            HStack(spacing: 12) {
                BrowserIcon(browser: browser)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Using \(browser.name) temporarily").font(.body.weight(.medium))
                    Text(store.activeLeaseRemainingText ?? "Until you stop").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("End") { _ = store.endBrowserLease() }.accessibilityIdentifier("end-temporary-browser")
            }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
        if store.canUndoLease { Button("Undo temporary browser change") { _ = store.undoBrowserLeaseChange() } }
    }
}

struct SelectorChoice: Identifiable {
    let id: String
    let title: String
    var icon: NSImage? = nil
    var symbol: String? = nil
}

struct WideSelector: View {
    let label: String
    let selectedID: String
    let choices: [SelectorChoice]
    var placeholder = "Choose a browser"
    @Binding var isPresented: Bool
    let choose: (String) -> Void
    @State private var highlighted = 0
    @FocusState private var choicesFocused: Bool
    private var current: SelectorChoice? { choices.first { $0.id == selectedID } }
    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 12) {
                choiceIcon(current)
                Text(current?.title ?? placeholder).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                Spacer(minLength: 10)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 9).frame(minHeight: 42).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.7))
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityValue(current?.title ?? "Choose a browser")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(label).font(.headline).padding(.horizontal, 8)
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(Array(choices.enumerated()), id: \.element.id) { index, option in
                                Button { pick(option.id) } label: {
                                    HStack(spacing: 10) {
                                        choiceIcon(option)
                                        Text(option.title).fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 8)
                                        if option.id == selectedID { Image(systemName: "checkmark").foregroundStyle(.blue) }
                                    }.padding(9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                        .background(index == highlighted ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).accessibilityIdentifier("selector-choice-\(option.id)")
                            }
                        }
                    }.frame(maxHeight: 310)
                }.padding(12).frame(width: 320).focusable().focused($choicesFocused)
                    .onAppear { highlighted = choices.firstIndex { $0.id == selectedID } ?? 0; choicesFocused = true }
                    .onKeyPress(.downArrow) { highlighted = min(choices.count - 1, highlighted + 1); return .handled }
                    .onKeyPress(.upArrow) { highlighted = max(0, highlighted - 1); return .handled }
                    .onKeyPress(.return) { if choices.indices.contains(highlighted) { pick(choices[highlighted].id) }; return .handled }
                    .onKeyPress(.escape) { isPresented = false; return .handled }
            }
    }
    @ViewBuilder private func choiceIcon(_ option: SelectorChoice?) -> some View {
        if let icon = option?.icon { Image(nsImage: icon).resizable().frame(width: 24, height: 24).accessibilityHidden(true) }
        else if let symbol = option?.symbol { Image(systemName: symbol).font(.system(size: 23)).foregroundStyle(.secondary).frame(width: 24).accessibilityHidden(true) }
    }
    private func pick(_ id: String) { isPresented = false; choose(id) }
}
