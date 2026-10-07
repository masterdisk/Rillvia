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
            else { Image(systemName: "globe").resizable().scaledToFit().foregroundStyle(AppColors.secondaryText).padding(2) }
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
            Text(title).appFont(size: size, weight: .bold).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier(identifier)
            if let subtitle { Text(subtitle).appFont(size: 15).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true) }
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
            Text(title).appFont(size: 14, weight: .medium).fixedSize(horizontal: false, vertical: true)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .contain)
    }
}

struct ShortcutHint: View {
    let keys: String
    var body: some View {
        Text(keys).appFont(size: 12, weight: .medium).foregroundStyle(AppColors.secondaryText)
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
                .appFont(size: store.isSmartRoutingActive ? 8 : 13)
                .foregroundStyle(store.isSmartRoutingActive ? Color.green : Color.secondary)
        }
            .appFont(size: 13, weight: .medium)
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
                Image(systemName: "info.circle").foregroundStyle(AppColors.secondaryText)
                Text(message).appFont(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
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
                .modifier(AccessibleGlassStyle(prominent: true)).keyboardShortcut(.defaultAction)
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
    @State private var browserPicker = false
    @State private var durationPicker = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldCaption(title: "Browser") {
                WideSelector(label: "Temporary browser", selectedID: browserID,
                    choices: store.externalBrowsers.map { SelectorChoice(id: $0.id, title: $0.name, icon: store.icon(for: $0)) },
                    isPresented: $browserPicker) { browserID = $0 }.accessibilityIdentifier("temporary-browser-picker")
            }
            FieldCaption(title: "For how long?") {
                WideSelector(label: "Duration", selectedID: duration.rawValue,
                    choices: BrowserLeasePreset.allCases.map { SelectorChoice(id: $0.rawValue, title: $0.title, symbol: "timer") },
                    isPresented: $durationPicker) { if let value = BrowserLeasePreset(rawValue: $0) { duration = value } }
                    .accessibilityIdentifier("temporary-duration-picker")
            }
            if !store.isSmartRoutingActive {
                Text("Turn on rules in Overview to use a temporary browser.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
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
                    Text("Using \(browser.name) temporarily").appFont(.body, weight: .medium)
                    Text(store.activeLeaseRemainingText ?? "Until you stop").appFont(.callout).foregroundStyle(AppColors.secondaryText)
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
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.rillviaIncreaseContrastOverride) private var testingIncreasedContrast
    @Environment(\.rillviaTextScale) private var textScale
    private var iconSize: CGFloat { 24 * textScale }
    let label: String
    let selectedID: String
    let choices: [SelectorChoice]
    var placeholder = "Choose a browser"
    @Binding var isPresented: Bool
    let choose: (String) -> Void
    @State private var focusedChoice: String?
    @FocusState private var choicesFocused: Bool
    @FocusState private var triggerFocused: Bool
    private var current: SelectorChoice? { choices.first { $0.id == selectedID } }
    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 12) {
                choiceIcon(current)
                Text(current?.title ?? placeholder).appFont(size: 15).fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                Spacer(minLength: 10)
                Image(systemName: "chevron.down").appFont(size: 12, weight: .semibold).foregroundStyle(AppColors.secondaryText).accessibilityHidden(true)
            }.padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 44 * textScale).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(triggerFocused ? Color.primary : contrast == .increased || testingIncreasedContrast ? Color.primary : AppColors.controlBorder, lineWidth: triggerFocused ? 2 : 1))
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityValue(current?.title ?? "Choose a browser")
            .focusable().focusEffectDisabled().focused($triggerFocused)
            .accessibilityHint("Opens choices. Use arrow keys to move, Return to choose, and Escape to close.")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) { selectionPopover }
            .onChange(of: isPresented) { _, visible in if !visible { triggerFocused = true } }
    }
    private var selectionPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).appFont(.headline).padding(.horizontal, 8).accessibilityAddTraits(.isHeader)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(choices) { option in choiceRow(option).id(option.id) }
                    }
                }.frame(maxHeight: 310)
                    .onChange(of: focusedChoice) { _, id in if let id { proxy.scrollTo(id) } }
            }
        }.padding(12).frame(width: 320).accessibilityElement(children: .contain)
            .focusable().focusEffectDisabled().focused($choicesFocused)
            .onAppear { focusedChoice = current?.id ?? choices.first?.id; choicesFocused = true }
            .onKeyPress(.downArrow) { moveFocus(by: 1); return .handled }
            .onKeyPress(.upArrow) { moveFocus(by: -1); return .handled }
            .onKeyPress(.return) { if let id = focusedChoice { pick(id) }; return .handled }
            .onKeyPress(.escape) { isPresented = false; return .handled }
    }
    private func choiceRow(_ option: SelectorChoice) -> some View {
        Button { pick(option.id) } label: {
            HStack(spacing: 10) {
                choiceIcon(option)
                Text(option.title).appFont(size: 15).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if option.id == selectedID { Image(systemName: "checkmark").foregroundStyle(.primary).accessibilityHidden(true) }
            }.padding(.horizontal, 10).padding(.vertical, 10).frame(minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .background(option.id == selectedID ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focusedChoice == option.id ? Color.primary : .clear, lineWidth: 2))
        }.buttonStyle(.plain)
            .accessibilityLabel(option.title).accessibilityAddTraits(option.id == selectedID ? [.isSelected] : [])
            .accessibilityIdentifier("selector-choice-\(option.id)")
    }
    @ViewBuilder private func choiceIcon(_ option: SelectorChoice?) -> some View {
        if let icon = option?.icon { Image(nsImage: icon).resizable().scaledToFit().frame(width: iconSize, height: iconSize).accessibilityHidden(true) }
        else if let symbol = option?.symbol { Image(systemName: symbol).resizable().scaledToFit().foregroundStyle(AppColors.secondaryText).frame(width: iconSize, height: iconSize).accessibilityHidden(true) }
    }
    private func moveFocus(by offset: Int) {
        guard !choices.isEmpty else { return }
        let index = choices.firstIndex { $0.id == focusedChoice } ?? 0
        focusedChoice = choices[min(choices.count - 1, max(0, index + offset))].id
        if let id = focusedChoice, let option = choices.first(where: { $0.id == id }) { AccessibilityAnnouncement.post(option.title) }
    }
    private func pick(_ id: String) { isPresented = false; choose(id) }
}
