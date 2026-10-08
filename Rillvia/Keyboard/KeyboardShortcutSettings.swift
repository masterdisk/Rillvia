import AppKit
import SwiftUI

struct KeyboardShortcutSettings: View {
    @Environment(BrowserStore.self) private var store
    @State private var editing: ShortcutBinding?
    @State private var error: String?
    @State private var confirmReset = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your shortcuts").fontWeight(.medium)
                    Text("Pick keys, then choose what they do—even while another app is open.")
                        .appFont(.callout).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Add shortcut", systemImage: "plus") {
                    var binding = ShortcutBinding()
                    binding.action.browserID = store.externalBrowsers.first { $0.id == "com.google.Chrome" }?.id ?? store.externalBrowsers.first?.id ?? ""
                    editing = binding
                }.modifier(AccessibleButtonStyle()).disabled(store.shortcuts.loadError != nil).accessibilityIdentifier("add-keyboard-shortcut")
            }
            if let loadError = store.shortcuts.loadError {
                Text(loadError).appFont(.callout).foregroundStyle(AppColors.errorText).fixedSize(horizontal: false, vertical: true)
                Button("Reset saved shortcuts") { confirmReset = true }
            } else if store.shortcuts.bindings.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard").appFont(.title2).foregroundStyle(AppColors.secondaryText)
                    Text("Try ⌃⌥⇧C for Chrome, or ⌃⌥W for your Work rule set.")
                        .appFont(.callout).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 8).accessibilityIdentifier("keyboard-shortcuts-empty")
            } else {
                ForEach(store.shortcuts.bindings) { binding in
                    Divider()
                    HStack(alignment: .center, spacing: 12) {
                        Button { editing = binding } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ShortcutExecutor.title(binding.action, in: store)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                                Text(binding.scope.title).appFont(.caption).foregroundStyle(AppColors.secondaryText)
                                if let issue = store.shortcuts.registrationIssues[binding.id] ?? ShortcutExecutor.configurationProblem(binding.action, in: store) {
                                    Text(issue).appFont(.caption).foregroundStyle(AppColors.warningText).fixedSize(horizontal: false, vertical: true)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("edit-shortcut-\(binding.id)")
                        Text(binding.chord?.display ?? "No keys").appFont(.callout, design: .monospaced).fixedSize()
                        Toggle("Enable shortcut", isOn: Binding(get: { binding.isEnabled }, set: { error = store.shortcuts.setEnabled($0, id: binding.id) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                            .accessibilityLabel("Enable \(ShortcutExecutor.title(binding.action, in: store)) shortcut")
                            .accessibilityIdentifier("shortcut-enabled-\(binding.id)")
                        Button { store.shortcuts.remove(binding.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).accessibilityLabel("Delete \(ShortcutExecutor.title(binding.action, in: store)) shortcut").accessibilityIdentifier("delete-shortcut-\(binding.id)")
                    }
                }
            }
            if let error { Text(error).appFont(.callout).foregroundStyle(AppColors.errorText).fixedSize(horizontal: false, vertical: true) }
            if let message = store.shortcuts.lastMessage {
                Text("Last shortcut: \(message)").appFont(.callout).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("last-keyboard-shortcut")
            }
            HStack {
                Button("View built-in shortcuts") { store.workspace.showKeyboardShortcuts = true }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText)
                Spacer()
                if store.shortcuts.canUndoRemoval {
                    Button("Undo deletion") { error = store.shortcuts.undoRemoval() }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText).accessibilityIdentifier("undo-shortcut-deletion")
                }
            }
        }
        .sheet(item: $editing, onDismiss: { store.shortcuts.isEditing = false }) { binding in
            KeyboardShortcutEditor(binding: binding).environment(store)
        }
        .alert("Reset saved shortcuts?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { store.shortcuts.resetUnreadable() }
        } message: { Text("A backup of the unreadable data will be kept. Your browsers and rules stay as they are.") }
    }
}

private struct KeyboardShortcutEditor: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ShortcutBinding
    @State private var recording = false
    @State private var actionPicker = false
    @State private var browserPicker = false
    @State private var ruleSetPicker = false
    @State private var durationPicker = false
    @State private var scopePicker = false
    @Environment(\.rillviaTextScale) private var textScale
    @State private var error: String?
    init(binding: ShortcutBinding) { _draft = State(initialValue: binding) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: store.shortcuts.bindings.contains { $0.id == draft.id } ? "Edit shortcut" : "New shortcut", subtitle: "Choose keys and what they do.", identifier: "shortcut-editor-title")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FieldCaption(title: "Key combination") {
                        HStack(spacing: 12) {
                            Button { recording.toggle() } label: {
                                Label(recording ? "Press your keys…" : draft.chord?.display ?? "Record shortcut", systemImage: "keyboard")
                                    .appFont(size: 17, weight: .medium, design: .monospaced).frame(minHeight: 24)
                            }.modifier(AccessibleButtonStyle()).controlSize(.large).accessibilityIdentifier("record-shortcut")
                            if draft.chord != nil, !recording { Button("Clear") { draft.chord = nil }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText) }
                        }
                        Text(recording ? "Press a combination with ⌘ or ⌃. Esc stops recording." : "Click Record shortcut, then press the keys together. Try ⌃⌥⇧C.")
                            .appFont(.callout).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                    }
                    FieldCaption(title: "Works") {
                        if textScale > 1.25 {
                            WideSelector(label: "Shortcut scope", selectedID: draft.scope.rawValue,
                                choices: ShortcutScope.allCases.map { SelectorChoice(id: $0.rawValue, title: $0.title) },
                                isPresented: $scopePicker) { if let value = ShortcutScope(rawValue: $0) { draft.scope = value } }
                                .accessibilityIdentifier("shortcut-scope")
                        } else {
                        Picker("Shortcut scope", selection: $draft.scope) {
                            ForEach(ShortcutScope.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).fixedSize().accessibilityIdentifier("shortcut-scope")
                        }
                    }
                    FieldCaption(title: "Action") {
                        WideSelector(label: "Shortcut action", selectedID: draft.action.kind.rawValue,
                            choices: ShortcutActionKind.allCases.map { SelectorChoice(id: $0.rawValue, title: $0.title) }, isPresented: $actionPicker) { id in
                            if let kind = ShortcutActionKind(rawValue: id) { draft.action.kind = kind }
                        }.accessibilityIdentifier("shortcut-action-picker")
                        Text(draft.action.kind.detail).appFont(.callout).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                    }
                    if draft.action.kind.needsBrowser {
                        FieldCaption(title: "Browser") {
                            WideSelector(label: "Shortcut browser", selectedID: draft.action.browserID,
                                choices: store.externalBrowsers.map { SelectorChoice(id: $0.id, title: $0.name, icon: store.icon(for: $0)) }, isPresented: $browserPicker) { draft.action.browserID = $0 }
                                .accessibilityIdentifier("shortcut-browser-picker")
                        }
                    }
                    if draft.action.kind == .temporaryBrowser {
                        FieldCaption(title: "For how long?") {
                            WideSelector(label: "Shortcut duration", selectedID: draft.action.duration.rawValue,
                                choices: BrowserLeasePreset.allCases.map { SelectorChoice(id: $0.rawValue, title: $0.title, symbol: "timer") },
                                isPresented: $durationPicker) { if let value = BrowserLeasePreset(rawValue: $0) { draft.action.duration = value } }
                                .accessibilityIdentifier("shortcut-duration-picker")
                        }
                    }
                    if draft.action.kind == .ruleSet {
                        FieldCaption(title: "Rule set") {
                            WideSelector(label: "Shortcut rule set", selectedID: draft.action.ruleSetID,
                                choices: [SelectorChoice(id: "shared", title: "Shared rules only", symbol: "square.3.layers.3d")] + store.routingConfiguration.profiles.filter(\.isEnabled).map { SelectorChoice(id: $0.id.uuidString, title: $0.name, symbol: "square.3.layers.3d") }, placeholder: "Choose a rule set", isPresented: $ruleSetPicker) { draft.action.ruleSetID = $0 }
                                .accessibilityIdentifier("shortcut-rule-set-picker")
                        }
                    }
                    if let problem = error ?? (draft.chord == nil ? nil : store.shortcuts.problem(for: draft)) {
                        Label(problem, systemImage: "exclamationmark.circle").appFont(.callout).foregroundStyle(AppColors.errorText).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("shortcut-validation-error")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 2)
            }
            Text("Your shortcuts pause while this editor is open.").appFont(.caption).foregroundStyle(AppColors.secondaryText)
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("cancel-keyboard-shortcut")
                Spacer()
                Button("Save shortcut") {
                    recording = false
                    if let problem = store.shortcuts.save(draft) { error = problem }
                    else { dismiss() }
                }.modifier(AccessibleButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    .disabled(recording || draft.chord == nil || store.shortcuts.problem(for: draft) != nil || error != nil)
                    .accessibilityIdentifier("save-keyboard-shortcut")
            }
        }.padding(28).frame(width: 580, height: 620)
        .background(ShortcutRecorder(recording: $recording, chord: $draft.chord).frame(width: 0, height: 0))
        .onAppear { store.shortcuts.isEditing = true; check() }
        .onChange(of: draft) { _, _ in check() }
        .onChange(of: recording) { _, value in if !value { check() } }
        .onDisappear { store.shortcuts.isEditing = false }
    }
    private func check() {
        error = draft.chord == nil ? nil : store.shortcuts.problem(for: draft) ?? store.shortcuts.validateSystemShortcut?(draft)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var recording: Bool
    @Binding var chord: ShortcutChord?
    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.recording = recording
        view.capture = { chord = $0; recording = false }
        view.cancel = { recording = false }
    }
    static func dismantleNSView(_ view: CaptureView, coordinator: ()) { view.stop() }
    final class CaptureView: NSView {
        var recording = false
        var capture: ((ShortcutChord) -> Void)?
        var cancel: (() -> Void)?
        private var monitor: Any?
        override init(frame: NSRect) {
            super.init(frame: frame)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.recording, self.window != nil, NSApp.keyWindow === self.window else { return event }
                if event.keyCode == 53, ShortcutModifiers(event.modifierFlags).isEmpty { self.cancel?() }
                else { self.capture?(ShortcutChord.recorded(from: event)) }
                return nil
            }
        }
        convenience init() { self.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
    }
}
