import AppKit
import Foundation
import Observation

struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt32
    static let command = Self(rawValue: 1)
    static let option = Self(rawValue: 2)
    static let control = Self(rawValue: 4)
    static let shift = Self(rawValue: 8)

    init(rawValue: UInt32) { self.rawValue = rawValue }
    init(_ flags: NSEvent.ModifierFlags) {
        var result: Self = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        self = result
    }
    var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

struct ShortcutChord: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: ShortcutModifiers
    var key: String
    var display: String { modifiers.symbols + key.uppercased() }
    var fingerprint: String { "\(keyCode):\(modifiers.rawValue)" }
    func matches(_ event: NSEvent) -> Bool { keyCode == UInt32(event.keyCode) && modifiers == ShortcutModifiers(event.modifierFlags) }

    static func recorded(from event: NSEvent) -> Self {
        let special: [UInt16: String] = [36: "↩", 48: "Tab", 49: "Space", 51: "⌫", 53: "Esc", 76: "↩", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        return Self(keyCode: UInt32(event.keyCode), modifiers: ShortcutModifiers(event.modifierFlags), key: special[event.keyCode] ?? event.charactersIgnoringModifiers ?? "")
    }

    var problem: String? {
        guard keyCode <= 126, !key.isEmpty, key.count <= 16, modifiers.rawValue & ~15 == 0 else { return "Record a key combination first." }
        guard modifiers.contains(.command) || modifiers.contains(.control) else { return "Include ⌘ or ⌃ so the shortcut does not replace ordinary typing." }
        // Keep the existing app commands and standard text editing available.
        if modifiers == .command, [0, 1, 3, 4, 6, 7, 8, 9, 11, 12, 13, 17, 18, 19, 20, 21, 31, 36, 37, 43, 44, 45, 46, 48, 49].contains(keyCode) {
            return "\(display) is already used by Rillvia or macOS. Choose another combination."
        }
        if modifiers == [.command, .shift], [6, 15, 20, 21, 23, 48].contains(keyCode) {
            return "\(display) is already used by Rillvia or macOS. Choose another combination."
        }
        if modifiers == [.command, .option], [17, 32, 53].contains(keyCode) {
            return "\(display) is already used by Rillvia or macOS. Choose another combination."
        }
        return nil
    }
}

enum ShortcutScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case everywhere, rillvia
    var id: Self { self }
    var title: String { self == .everywhere ? "Everywhere" : "In Rillvia" }
}

enum ShortcutActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case useBrowser, temporaryBrowser, endTemporaryBrowser, ruleSet, nextRuleSet, openApp, previewClipboard
    var id: Self { self }
    var title: String {
        switch self {
        case .useBrowser: "Use a browser for links"
        case .temporaryBrowser: "Use a browser temporarily"
        case .endTemporaryBrowser: "End the temporary browser"
        case .ruleSet: "Switch rule set"
        case .nextRuleSet: "Next rule set"
        case .openApp: "Open Rillvia"
        case .previewClipboard: "Preview the clipboard link"
        }
    }
    var needsBrowser: Bool { self == .useBrowser || self == .temporaryBrowser }
    var detail: String {
        switch self {
        case .useBrowser: "With rules set up, this changes Other links. Without rules, it changes the macOS default browser."
        case .temporaryBrowser: "All links use this browser for the time you choose. Rules must be on."
        case .endTemporaryBrowser: "End the current temporary choice and resume your rules."
        case .ruleSet: "Use this set alongside your shared rules. It does not turn rules on or off."
        case .nextRuleSet: "Cycle through your enabled rule sets and Shared rules only."
        case .openApp: "Bring Rillvia to the front."
        case .previewClipboard: "Preview a copied web link in Rillvia. The link stays unopened."
        }
    }
}

struct ShortcutAction: Codable, Equatable, Sendable {
    var kind: ShortcutActionKind = .useBrowser
    var browserID = ""
    var ruleSetID = "shared"
    var duration: BrowserLeasePreset = .fifteenMinutes
    var problem: String? {
        if kind.needsBrowser, browserID.isEmpty { return "Choose a browser." }
        if kind == .ruleSet, ruleSetID != "shared", UUID(uuidString: ruleSetID) == nil { return "Choose a rule set." }
        return nil
    }
}

struct ShortcutBinding: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var chord: ShortcutChord?
    var scope: ShortcutScope = .everywhere
    var action = ShortcutAction()
    var isEnabled = true
}

private struct ShortcutConfiguration: Codable {
    var version = 1
    var bindings: [ShortcutBinding]
}

@MainActor
@Observable
final class KeyboardShortcutStore {
    static let preferencesKey = "keyboardShortcuts.v1"
    private(set) var bindings: [ShortcutBinding] = []
    private(set) var loadError: String?
    var registrationIssues: [UUID: String] = [:]
    var lastMessage: String?
    var isEditing = false { didSet { onChange?() } }
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var validateSystemShortcut: ((ShortcutBinding) -> String?)?
    @ObservationIgnored private let defaults: UserDefaults
    private var removedBinding: ShortcutBinding?
    var canUndoRemoval: Bool { removedBinding != nil }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.preferencesKey) else { return }
        do {
            let configuration = try JSONDecoder().decode(ShortcutConfiguration.self, from: data)
            guard configuration.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            guard Set(configuration.bindings.map(\.id)).count == configuration.bindings.count else { throw CocoaError(.coderReadCorrupt) }
            bindings = configuration.bindings
        } catch {
            loadError = "Saved shortcuts could not be read. Reset them to start again; the previous data will be kept as a backup."
        }
    }

    func problem(for binding: ShortcutBinding) -> String? {
        if let loadError { return loadError }
        guard let chord = binding.chord else { return "Record a key combination first." }
        if let problem = chord.problem ?? binding.action.problem { return problem }
        if binding.isEnabled, bindings.contains(where: { $0.id != binding.id && $0.isEnabled && $0.chord?.fingerprint == chord.fingerprint }) {
            return "\(chord.display) is assigned to another shortcut. Edit that shortcut or choose different keys."
        }
        return nil
    }

    @discardableResult func save(_ binding: ShortcutBinding) -> String? {
        if let problem = problem(for: binding) ?? validateSystemShortcut?(binding) { return problem }
        var next = bindings
        if let index = next.firstIndex(where: { $0.id == binding.id }) { next[index] = binding }
        else { next.append(binding) }
        return persist(next)
    }

    @discardableResult func setEnabled(_ enabled: Bool, id: UUID) -> String? {
        guard var binding = bindings.first(where: { $0.id == id }) else { return "This shortcut no longer exists." }
        binding.isEnabled = enabled
        if !enabled { return persist(bindings.map { $0.id == id ? binding : $0 }) }
        return save(binding)
    }

    func remove(_ id: UUID) {
        guard let binding = bindings.first(where: { $0.id == id }) else { return }
        if persist(bindings.filter { $0.id != id }) == nil { removedBinding = binding }
    }

    @discardableResult func undoRemoval() -> String? {
        guard let binding = removedBinding else { return nil }
        if let problem = save(binding) { return problem }
        removedBinding = nil
        return nil
    }

    func resetUnreadable() {
        guard loadError != nil else { return }
        if let data = defaults.data(forKey: Self.preferencesKey) { defaults.set(data, forKey: Self.preferencesKey + ".backup") }
        loadError = nil
        _ = persist([])
    }

    private func persist(_ next: [ShortcutBinding]) -> String? {
        do {
            let data = try JSONEncoder().encode(ShortcutConfiguration(bindings: next))
            defaults.set(data, forKey: Self.preferencesKey)
            bindings = next
            onChange?()
            return nil
        } catch { return "The shortcut could not be saved. Try again." }
    }
}
