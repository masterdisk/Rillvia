import Foundation

protocol VersionedPersistedState: Codable {
    static var currentSchemaVersion: Int { get }
    static var fresh: Self { get }
    var schemaVersion: Int { get }
}

extension RoutingConfiguration: VersionedPersistedState {}

struct HandlerUndoReceipt: Codable, Equatable, Sendable {
    var operationID: UUID
    var issuedAt: Date
    /// Undo is valid only while the live handlers still match this snapshot.
    var precondition: HTTPHandlerSnapshot
    var restore: HTTPHandlerSnapshot
}

struct PendingHandlerOperation: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var startedAt: Date
    var desiredHandlers: HTTPHandlerSnapshot
    var undoReceipt: HandlerUndoReceipt
}

struct HandlerOperationJournal: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var pendingOperation: PendingHandlerOperation?

    init(
        schemaVersion: Int = currentSchemaVersion,
        pendingOperation: PendingHandlerOperation? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.pendingOperation = pendingOperation
    }

    static let fresh = HandlerOperationJournal()
}

extension HandlerOperationJournal: VersionedPersistedState {}

struct ConfigurationHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var recordedAt: Date
    var configuration: RoutingConfiguration
}

struct ConfigurationHistory: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var entries: [ConfigurationHistoryEntry]

    init(
        schemaVersion: Int = currentSchemaVersion,
        entries: [ConfigurationHistoryEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    static let fresh = ConfigurationHistory()
}

extension ConfigurationHistory: VersionedPersistedState {}
