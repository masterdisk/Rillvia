import Foundation
import Observation

struct RuleDraft: Equatable {
    var id: UUID?
    var domain = ""
    var scope: DomainRuleScope = .exactHost
    var browserID = ""
    var browserProfileID = ""
    var profileID: UUID?
    var isEnabled = true

    init(rule: DomainRule) {
        id = rule.id
        domain = rule.domain
        scope = rule.scope
        browserID = rule.browser.bundleIdentifier
        browserProfileID = rule.browserProfile?.id ?? ""
        profileID = rule.profileID
        isEnabled = rule.isEnabled
    }

    init(browserID: String, profileID: UUID?) {
        self.browserID = browserID
        self.profileID = profileID
    }

    var normalizedDomain: String? { try? URLNormalizer.normalizeHost(domain) }
}

enum WorkspaceFocus: Equatable {
    case none, url, fallback, ruleSet, search
}

@MainActor
@Observable
final class WorkspaceModel {
    var previewInput = ""
    var previewedInput = ""
    var previewedRevision = -1
    var draft: RuleDraft?
    var savedDraft: RuleDraft?
    var browsedProfileID: UUID?
    var didChooseRuleSet = false
    var ruleSearch = ""
    var browserSearch = ""
    var chooserItem: AirlockItem?
    var showTemporaryBrowser = false
    var showKeyboardShortcuts = false
    var showTutorial = false
    var showRuleSets = false
    var showDiscardChanges = false
    var focus: WorkspaceFocus = .url
    var focusRequest = UUID()
    @ObservationIgnored private var pendingAction: (() -> Void)?

    var hasUnsavedRule: Bool { draft != nil && draft != savedDraft }

    func request(_ action: @escaping () -> Void) {
        if hasUnsavedRule {
            pendingAction = action
            showDiscardChanges = true
        } else {
            action()
        }
    }

    func discardAndContinue() {
        draft = savedDraft
        let action = pendingAction
        pendingAction = nil
        action?()
    }

    func keepEditing() { pendingAction = nil }

    func requestFocus(_ target: WorkspaceFocus) {
        focus = target
        focusRequest = UUID()
    }

    func load(_ rule: DomainRule) {
        draft = RuleDraft(rule: rule)
        savedDraft = draft
    }

    func startRule(browserID: String, profileID: UUID?) {
        draft = RuleDraft(browserID: browserID, profileID: profileID)
        savedDraft = nil
    }

    func cancelRule() { draft = savedDraft }

    func markPreview(input: String, revision: Int) {
        previewedInput = input
        previewedRevision = revision
    }

    func previewIsCurrent(revision: Int) -> Bool {
        !previewedInput.isEmpty && previewInput == previewedInput && revision == previewedRevision
    }
}
