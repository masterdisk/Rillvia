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

enum HandlerOperationKind: String, Codable, Equatable, Sendable {
    case direct
    case undo
    case smartActivation
    case smartDeactivation
}

struct PendingHandlerOperation: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var startedAt: Date
    var kind: HandlerOperationKind = .direct
    var desiredHandlers: HTTPHandlerSnapshot
    var undoReceipt: HandlerUndoReceipt
    /// Schemes this operation actually changed and therefore owns for rollback.
    var completedSchemes: [WebScheme] = []
    /// The write intent persisted before mutating Launch Services.
    var inFlightScheme: WebScheme?
    /// Smart transitions keep configuration coupled to handler verification.
    var configurationBefore: RoutingConfiguration?
    var configurationOnSuccess: RoutingConfiguration?

    private enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case kind
        case desiredHandlers
        case undoReceipt
        case completedSchemes
        case inFlightScheme
        case configurationBefore
        case configurationOnSuccess
    }

    init(
        id: UUID,
        startedAt: Date,
        kind: HandlerOperationKind = .direct,
        desiredHandlers: HTTPHandlerSnapshot,
        undoReceipt: HandlerUndoReceipt,
        completedSchemes: [WebScheme] = [],
        inFlightScheme: WebScheme? = nil,
        configurationBefore: RoutingConfiguration? = nil,
        configurationOnSuccess: RoutingConfiguration? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.kind = kind
        self.desiredHandlers = desiredHandlers
        self.undoReceipt = undoReceipt
        self.completedSchemes = completedSchemes
        self.inFlightScheme = inFlightScheme
        self.configurationBefore = configurationBefore
        self.configurationOnSuccess = configurationOnSuccess
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        kind = try values.decodeIfPresent(
            HandlerOperationKind.self,
            forKey: .kind
        ) ?? .direct
        desiredHandlers = try values.decode(
            HTTPHandlerSnapshot.self,
            forKey: .desiredHandlers
        )
        undoReceipt = try values.decode(
            HandlerUndoReceipt.self,
            forKey: .undoReceipt
        )
        completedSchemes = try values.decodeIfPresent(
            [WebScheme].self,
            forKey: .completedSchemes
        ) ?? []
        inFlightScheme = try values.decodeIfPresent(
            WebScheme.self,
            forKey: .inFlightScheme
        )
        configurationBefore = try values.decodeIfPresent(
            RoutingConfiguration.self,
            forKey: .configurationBefore
        )
        configurationOnSuccess = try values.decodeIfPresent(
            RoutingConfiguration.self,
            forKey: .configurationOnSuccess
        )
    }
}

struct HandlerOperationJournal: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 4

    var schemaVersion: Int
    var pendingOperation: PendingHandlerOperation?
    var undoReceipt: HandlerUndoReceipt?

    init(
        schemaVersion: Int = currentSchemaVersion,
        pendingOperation: PendingHandlerOperation? = nil,
        undoReceipt: HandlerUndoReceipt? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.pendingOperation = pendingOperation
        self.undoReceipt = undoReceipt
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
