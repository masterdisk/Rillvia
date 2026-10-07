import AppKit
import Carbon

@MainActor
protocol HotKeyRegistering: AnyObject {
    var onPress: ((UUID) -> Void)? { get set }
    func register(_ id: UUID, chord: ShortcutChord) -> Bool
    func unregister(_ id: UUID)
    func removeAll()
}

private let rillviaHotKeySignature: OSType = 0x52696c6c
private let rillviaHotKeyHandler: EventHandlerUPP = { _, event, context in
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var identity = EventHotKeyID()
    guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identity) == noErr,
          identity.signature == rillviaHotKeySignature else { return OSStatus(eventNotHandledErr) }
    let registry = Unmanaged<SystemHotKeyRegistry>.fromOpaque(context).takeUnretainedValue()
    // Application event handlers run on the main event loop; Carbon registration is not thread safe.
    MainActor.assumeIsolated { registry.receive(identity.id, released: GetEventKind(event) == UInt32(kEventHotKeyReleased)) }
    return noErr
}

@MainActor
final class SystemHotKeyRegistry: HotKeyRegistering {
    var onPress: ((UUID) -> Void)?
    private var handler: EventHandlerRef?
    private var references: [UUID: EventHotKeyRef] = [:]
    private var identities: [UInt32: UUID] = [:]
    private var pressed: Set<UInt32> = []
    private var nextID: UInt32 = 1

    init() {
        let types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        types.withUnsafeBufferPointer {
            _ = InstallEventHandler(GetApplicationEventTarget(), rillviaHotKeyHandler, types.count, $0.baseAddress, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
    }
    deinit {
        for reference in references.values { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
    func register(_ id: UUID, chord: ShortcutChord) -> Bool {
        guard handler != nil, references[id] == nil else { return false }
        var flags: UInt32 = 0
        if chord.modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if chord.modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if chord.modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if chord.modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        let identity = nextID
        nextID &+= 1
        var reference: EventHotKeyRef?
        guard RegisterEventHotKey(chord.keyCode, flags, EventHotKeyID(signature: rillviaHotKeySignature, id: identity), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference) == noErr,
              let reference else { return false }
        references[id] = reference
        identities[identity] = id
        return true
    }
    func unregister(_ id: UUID) {
        if let reference = references.removeValue(forKey: id) { UnregisterEventHotKey(reference) }
        let keys = identities.filter { $0.value == id }.map(\.key)
        for key in keys { identities.removeValue(forKey: key); pressed.remove(key) }
    }
    func removeAll() {
        for reference in references.values { UnregisterEventHotKey(reference) }
        references.removeAll(); identities.removeAll(); pressed.removeAll()
    }
    fileprivate func receive(_ identity: UInt32, released: Bool) {
        guard let id = identities[identity] else { return }
        if released { pressed.remove(identity) }
        else if pressed.insert(identity).inserted { onPress?(id) }
    }
}

@MainActor
enum ShortcutExecutor {
    static func configurationProblem(_ action: ShortcutAction, in store: BrowserStore) -> String? {
        if let problem = action.problem { return problem }
        if action.kind.needsBrowser, !store.externalBrowsers.contains(where: { $0.id == action.browserID }) { return "This browser is no longer installed. Choose another browser." }
        if action.kind == .ruleSet, action.ruleSetID != "shared", !store.routingConfiguration.profiles.contains(where: { $0.id.uuidString == action.ruleSetID && $0.isEnabled }) { return "This rule set is missing or disabled. Choose another set." }
        return nil
    }

    static func run(_ action: ShortcutAction, in store: BrowserStore, openApp: () -> Void) async -> String? {
        guard !store.isSwitching else { return "A browser change is already in progress. Try again when it finishes." }
        store.refresh()
        if let problem = configurationProblem(action, in: store) { return problem }
        switch action.kind {
        case .useBrowser:
            guard let browser = store.externalBrowsers.first(where: { $0.id == action.browserID }) else { return "Choose an installed browser." }
            await store.makeDefault(browser)
            let target = store.isSmartRoutingConfigured ? store.smartFallbackBrowser?.id : store.defaultBundleID
            return target == browser.id ? nil : store.message ?? "The browser could not be changed."
        case .temporaryBrowser:
            guard let browser = store.externalBrowsers.first(where: { $0.id == action.browserID }) else { return "Choose an installed browser." }
            return store.borrowBrowser(browser, for: action.duration) ? nil : store.message ?? "Turn on rules before using a temporary browser."
        case .endTemporaryBrowser:
            return store.endBrowserLease() ? nil : store.message ?? "There is no temporary browser to end."
        case .ruleSet:
            let id = action.ruleSetID == "shared" ? nil : UUID(uuidString: action.ruleSetID)
            return store.selectProfile(id) ? nil : store.message ?? "The rule set could not be changed."
        case .nextRuleSet:
            let choices: [UUID?] = [nil] + store.routingConfiguration.profiles.filter(\.isEnabled).map { Optional($0.id) }
            guard choices.count > 1 else { return "Add a rule set in Rules before cycling between sets." }
            let index = choices.firstIndex(of: store.routingConfiguration.activeProfileID) ?? -1
            return store.selectProfile(choices[(index + 1) % choices.count]) ? nil : store.message ?? "The rule set could not be changed."
        case .openApp: openApp(); return nil
        case .previewClipboard:
            guard store.stageClipboardURL() else { return "Copy a web link before using this shortcut." }
            store.workspace.previewInput = store.airlockResult.items.map(\.originalText).joined(separator: "\n")
            store.workspace.markPreview(input: store.workspace.previewInput, revision: store.revision)
            openApp()
            return nil
        }
    }

    static func title(_ action: ShortcutAction, in store: BrowserStore) -> String {
        let browser = store.externalBrowsers.first { $0.id == action.browserID }?.name ?? "Missing browser"
        switch action.kind {
        case .useBrowser: return "Use \(browser) for links"
        case .temporaryBrowser: return action.duration.actionTitle(browserName: browser)
        case .ruleSet: return "Switch to \(action.ruleSetID == "shared" ? "Shared rules only" : store.routingConfiguration.profiles.first { $0.id.uuidString == action.ruleSetID }?.name ?? "Missing rule set")"
        default: return action.kind.title
        }
    }
}

@MainActor
final class KeyboardShortcutController {
    private let store: BrowserStore
    private let registry: any HotKeyRegistering
    private let openApp: () -> Void
    private var localMonitor: Any?

    init(store: BrowserStore, registry: (any HotKeyRegistering)? = nil, openApp: @escaping () -> Void) {
        let registry = registry ?? SystemHotKeyRegistry()
        self.store = store; self.registry = registry; self.openApp = openApp
        registry.onPress = { [weak self] id in self?.invoke(id) }
        store.shortcuts.onChange = { [weak self] in self?.synchronize() }
        store.shortcuts.validateSystemShortcut = { [weak self] binding in self?.systemProblem(for: binding) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, !self.store.shortcuts.isEditing,
                      let binding = self.store.shortcuts.bindings.first(where: { $0.isEnabled && $0.scope == .rillvia && $0.chord?.matches(event) == true && self.store.shortcuts.registrationIssues[$0.id] == nil }) else { return false }
                if !event.isARepeat { self.invoke(binding.id) }
                return true
            }
            return handled ? nil : event
        }
        synchronize()
    }

    func stop() {
        registry.removeAll(); registry.onPress = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        store.shortcuts.onChange = nil; store.shortcuts.validateSystemShortcut = nil
    }

    private func synchronize() {
        registry.removeAll()
        store.shortcuts.registrationIssues = [:]
        guard !store.shortcuts.isEditing else { return }
        for binding in store.shortcuts.bindings where binding.isEnabled {
            if let problem = store.shortcuts.problem(for: binding) {
                store.shortcuts.registrationIssues[binding.id] = problem
            } else if binding.scope == .everywhere, let chord = binding.chord, !registry.register(binding.id, chord: chord) {
                store.shortcuts.registrationIssues[binding.id] = "macOS could not register this shortcut. Another app may be using it."
            }
        }
    }

    private func systemProblem(for binding: ShortcutBinding) -> String? {
        guard binding.isEnabled else { return nil }
        if let problem = ShortcutExecutor.configurationProblem(binding.action, in: store) { return problem }
        guard binding.isEnabled, binding.scope == .everywhere, let chord = binding.chord else { return nil }
        if !store.shortcuts.isEditing, store.shortcuts.bindings.contains(where: { $0.id == binding.id && $0.isEnabled && $0.scope == .everywhere && $0.chord?.fingerprint == chord.fingerprint }), store.shortcuts.registrationIssues[binding.id] == nil { return nil }
        let probe = UUID()
        guard registry.register(probe, chord: chord) else { return "macOS could not register \(chord.display). Another app may be using it. Choose different keys." }
        registry.unregister(probe)
        return nil
    }

    private func invoke(_ id: UUID) {
        guard !store.shortcuts.isEditing, let binding = store.shortcuts.bindings.first(where: { $0.id == id && $0.isEnabled }), store.shortcuts.problem(for: binding) == nil else { return }
        Task { @MainActor [weak self] in
            guard let self, !self.store.shortcuts.isEditing,
                  self.store.shortcuts.bindings.contains(where: { $0 == binding }) else { return }
            let problem = await ShortcutExecutor.run(binding.action, in: self.store, openApp: self.openApp)
            self.store.shortcuts.lastMessage = problem ?? ShortcutExecutor.title(binding.action, in: self.store)
            if problem != nil { NSSound.beep() }
        }
    }
}
