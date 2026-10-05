import Foundation

enum BrowserLeasePreset: String, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes
    case thirtyMinutes
    case sixtyMinutes
    case untilEnded

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .fifteenMinutes:
            "15 minutes"
        case .thirtyMinutes:
            "30 minutes"
        case .sixtyMinutes:
            "60 minutes"
        case .untilEnded:
            "Until ended"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .fifteenMinutes:
            15 * 60
        case .thirtyMinutes:
            30 * 60
        case .sixtyMinutes:
            60 * 60
        case .untilEnded:
            nil
        }
    }

    func actionTitle(browserName: String) -> String {
        switch self {
        case .untilEnded:
            "Borrow \(browserName) until ended"
        case .fifteenMinutes, .thirtyMinutes, .sixtyMinutes:
            "Borrow \(browserName) for \(title.lowercased())"
        }
    }

    func activeDescription(browserName: String) -> String {
        switch self {
        case .untilEnded:
            "\(browserName) is borrowed until ended"
        case .fifteenMinutes, .thirtyMinutes, .sixtyMinutes:
            "\(browserName) is borrowed for \(title.lowercased())"
        }
    }
}

enum BrowserLeaseIssue: Error, Equatable, Sendable {
    case smartRoutingUnavailable
    case selfTarget
    case targetUnavailable(BrowserReference)
    case noActiveLease
    case noUndoReceipt
    case undoPreconditionFailed
    case configurationPersistenceFailed
}

enum BrowserLeaseOutcome: Equatable, Sendable {
    case succeeded
    case failed(BrowserLeaseIssue)
}

struct BrowserLeaseReconciliation: Equatable, Sendable {
    var didExpire: Bool
    var issue: BrowserLeaseIssue?
}

enum BrowserLeaseFormatting {
    static func remainingText(
        for lease: BrowserLease,
        at date: Date
    ) -> String {
        guard let expiresAt = lease.expiresAt else {
            return "Until ended"
        }
        let totalSeconds = max(
            0,
            Int(ceil(expiresAt.timeIntervalSince(date)))
        )
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(
                format: "%d:%02d:%02d remaining",
                hours,
                minutes,
                seconds
            )
        }
        return String(
            format: "%d:%02d remaining",
            minutes,
            seconds
        )
    }
}

@MainActor
final class BrowserLeaseCoordinator {
    private struct UndoReceipt {
        var precondition: RoutingConfiguration
        var restore: BrowserLease?
    }

    private struct ScheduledExpiry: Equatable {
        var leaseID: UUID
        var deadline: Date
    }

    private let systemHandler: any SystemBrowserHandling
    private let repository: StateRepository
    private let browserChange: BrowserReference
    private let smartRoutingCoordinator: SmartRoutingCoordinator
    private let scheduler: any BrowserLeaseScheduling
    private let now: () -> Date

    private(set) var configuration: RoutingConfiguration = .fresh
    private var undoReceipt: UndoReceipt?
    private var scheduledExpiry: ScheduledExpiry?

    var onAutomaticExpiry: (() -> Void)?

    init(
        systemHandler: any SystemBrowserHandling,
        repository: StateRepository,
        browserChange: BrowserReference,
        smartRoutingCoordinator: SmartRoutingCoordinator,
        scheduler: any BrowserLeaseScheduling,
        now: @escaping () -> Date = Date.init
    ) {
        self.systemHandler = systemHandler
        self.repository = repository
        self.browserChange = browserChange
        self.smartRoutingCoordinator = smartRoutingCoordinator
        self.scheduler = scheduler
        self.now = now
    }

    var activeLease: BrowserLease? {
        configuration.browserLease
    }

    var canUndo: Bool {
        guard let undoReceipt else { return false }
        return configuration == undoReceipt.precondition
            && isUndoEligible(undoReceipt, at: now())
    }

    func startLease(
        to target: BrowserReference,
        preset: BrowserLeasePreset,
        availableTargets: Set<BrowserReference>? = nil
    ) -> BrowserLeaseOutcome {
        let reconciliation = reconcile(
            availableTargets: availableTargets
        )
        if reconciliation.issue == .configurationPersistenceFailed {
            return .failed(.configurationPersistenceFailed)
        }

        do {
            let current = try repository.loadConfiguration()
            configuration = current
            guard try smartRoutingCoordinator
                .isVerifiedSmartRoutingActive(configuration: current) else {
                return .failed(.smartRoutingUnavailable)
            }
            guard target != browserChange else {
                return .failed(.selfTarget)
            }
            guard isAvailable(
                target,
                availableTargets: availableTargets
            ) else {
                return .failed(.targetUnavailable(target))
            }

            let timestamp = now()
            let lease = BrowserLease(
                revision: (current.browserLease?.revision ?? 0) + 1,
                browser: target,
                startedAt: timestamp,
                expiresAt: preset.duration.map {
                    timestamp.addingTimeInterval($0)
                }
            )
            var desired = current
            desired.schemaVersion =
                RoutingConfiguration.currentSchemaVersion
            desired.browserLease = lease
            try repository.saveConfigurationSnapshot(
                desired,
                recordedAt: timestamp
            )

            undoReceipt = UndoReceipt(
                precondition: desired,
                restore: current.browserLease
            )
            configuration = desired
            reschedule(for: lease)
            return .succeeded
        } catch {
            return .failed(.configurationPersistenceFailed)
        }
    }

    func endLease() -> BrowserLeaseOutcome {
        _ = reconcile()
        do {
            let current = try repository.loadConfiguration()
            configuration = current
            guard let lease = current.browserLease else {
                return .failed(.noActiveLease)
            }

            var desired = current
            desired.schemaVersion =
                RoutingConfiguration.currentSchemaVersion
            desired.browserLease = nil
            try repository.saveConfigurationSnapshot(
                desired,
                recordedAt: now()
            )

            undoReceipt = UndoReceipt(
                precondition: desired,
                restore: lease
            )
            configuration = desired
            cancelScheduledExpiry()
            return .succeeded
        } catch {
            return .failed(.configurationPersistenceFailed)
        }
    }

    func undo() -> BrowserLeaseOutcome {
        let hadUndoReceipt = undoReceipt != nil
        let reconciliation = reconcile()
        if reconciliation.issue == .configurationPersistenceFailed {
            return .failed(.configurationPersistenceFailed)
        }
        guard let receipt = undoReceipt else {
            if hadUndoReceipt && !reconciliation.didExpire {
                return .failed(.undoPreconditionFailed)
            }
            return .failed(.noUndoReceipt)
        }
        do {
            let current = try repository.loadConfiguration()
            configuration = current
            guard current == receipt.precondition else {
                undoReceipt = nil
                return .failed(.undoPreconditionFailed)
            }
            guard isUndoEligible(receipt, at: now()) else {
                undoReceipt = nil
                return .failed(.noUndoReceipt)
            }

            var desired = current
            desired.schemaVersion =
                RoutingConfiguration.currentSchemaVersion
            desired.browserLease = receipt.restore
            try repository.saveConfigurationSnapshot(
                desired,
                recordedAt: now()
            )

            configuration = desired
            undoReceipt = nil
            reschedule(for: desired.browserLease)
            return .succeeded
        } catch {
            return .failed(.configurationPersistenceFailed)
        }
    }

    private func isUndoEligible(
        _ receipt: UndoReceipt,
        at date: Date
    ) -> Bool {
        if let lease = receipt.precondition.browserLease,
           !lease.isActive(at: date) {
            return false
        }
        if let lease = receipt.restore,
           !lease.isActive(at: date) {
            return false
        }
        return true
    }

    @discardableResult
    func reconcile(
        availableTargets: Set<BrowserReference>? = nil
    ) -> BrowserLeaseReconciliation {
        do {
            let current = try repository.loadConfiguration()
            configuration = current
            if let undoReceipt,
               current != undoReceipt.precondition {
                self.undoReceipt = nil
            }
            guard let lease = current.browserLease else {
                cancelScheduledExpiry()
                return BrowserLeaseReconciliation(
                    didExpire: false,
                    issue: nil
                )
            }

            guard current.mode == .smart else {
                var desired = current
                desired.schemaVersion =
                    RoutingConfiguration.currentSchemaVersion
                desired.browserLease = nil
                undoReceipt = nil
                try repository.saveConfigurationSnapshot(
                    desired,
                    recordedAt: now()
                )
                configuration = desired
                cancelScheduledExpiry()
                return BrowserLeaseReconciliation(
                    didExpire: false,
                    issue: nil
                )
            }

            guard lease.isActive(at: now()) else {
                var desired = current
                desired.schemaVersion =
                    RoutingConfiguration.currentSchemaVersion
                desired.browserLease = nil
                undoReceipt = nil
                try repository.saveConfigurationSnapshot(
                    desired,
                    recordedAt: now()
                )
                configuration = desired
                cancelScheduledExpiry()
                return BrowserLeaseReconciliation(
                    didExpire: true,
                    issue: nil
                )
            }

            reschedule(for: lease)
            let issue: BrowserLeaseIssue?
            if lease.browser == browserChange {
                issue = .selfTarget
            } else if !isAvailable(
                lease.browser,
                availableTargets: availableTargets
            ) {
                issue = .targetUnavailable(lease.browser)
            } else {
                issue = nil
            }
            return BrowserLeaseReconciliation(
                didExpire: false,
                issue: issue
            )
        } catch {
            return BrowserLeaseReconciliation(
                didExpire: false,
                issue: .configurationPersistenceFailed
            )
        }
    }

    func refreshConfiguration() {
        do {
            let current = try repository.loadConfiguration()
            configuration = current
            if let undoReceipt,
               current != undoReceipt.precondition {
                self.undoReceipt = nil
            }
            reschedule(
                for: current.mode == .smart
                    ? current.browserLease
                    : nil
            )
        } catch {
            undoReceipt = nil
        }
    }

    private func isAvailable(
        _ target: BrowserReference,
        availableTargets: Set<BrowserReference>?
    ) -> Bool {
        guard systemHandler.applicationURL(for: target) != nil else {
            return false
        }
        return availableTargets?.contains(target) ?? true
    }

    private func reschedule(for lease: BrowserLease?) {
        guard let lease, let deadline = lease.expiresAt else {
            cancelScheduledExpiry()
            return
        }
        let desired = ScheduledExpiry(
            leaseID: lease.id,
            deadline: deadline
        )
        guard desired != scheduledExpiry else { return }

        cancelScheduledExpiry()
        scheduledExpiry = desired
        scheduler.schedule(at: deadline) { [weak self] in
            guard let self else { return }
            self.scheduledExpiry = nil
            let result = self.reconcile()
            if result.didExpire {
                self.onAutomaticExpiry?()
            }
        }
    }

    private func cancelScheduledExpiry() {
        guard scheduledExpiry != nil else { return }
        scheduler.cancel()
        scheduledExpiry = nil
    }
}
