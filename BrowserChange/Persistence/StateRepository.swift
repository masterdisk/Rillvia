import Foundation

enum StateRepositoryError: Error, Equatable {
    case unsupportedSchema(
        fileName: String,
        found: Int,
        supported: Int
    )
}

extension StateRepositoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let fileName, let found, let supported):
            "\(fileName) uses schema \(found), but this version supports \(supported)."
        }
    }
}

struct PersistedSchemaVersions: Equatable, Sendable {
    var configuration: Int?
    var handlerJournal: Int?
    var configurationHistory: Int?
}

final class StateRepository {
    private enum FileName {
        static let configuration = "configuration.json"
        static let handlerJournal = "handler-journal.json"
        static let configurationHistory = "configuration-history.json"
    }

    let baseDirectory: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    convenience init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        self.init(
            baseDirectory: applicationSupport
                .appendingPathComponent("BrowserChange", isDirectory: true),
            fileManager: fileManager
        )
    }

    func loadConfiguration() throws -> RoutingConfiguration {
        try load(
            RoutingConfiguration.self,
            fileName: FileName.configuration
        )
    }

    func saveConfiguration(_ configuration: RoutingConfiguration) throws {
        try save(configuration, fileName: FileName.configuration)
    }

    func saveConfigurationSnapshot(
        _ configuration: RoutingConfiguration,
        snapshotID: UUID = UUID(),
        recordedAt: Date = .now,
        historyLimit: Int = 50
    ) throws {
        let previousHistory = try loadConfigurationHistory()
        let history = appendingSnapshot(
            of: configuration,
            snapshotID: snapshotID,
            recordedAt: recordedAt,
            historyLimit: historyLimit,
            to: previousHistory
        )

        try save(history, fileName: FileName.configurationHistory)
        do {
            try save(configuration, fileName: FileName.configuration)
        } catch {
            try? save(
                previousHistory,
                fileName: FileName.configurationHistory
            )
            throw error
        }
    }

    func appendConfigurationSnapshot(
        _ configuration: RoutingConfiguration,
        snapshotID: UUID = UUID(),
        recordedAt: Date = .now,
        historyLimit: Int = 50
    ) throws {
        let history = appendingSnapshot(
            of: configuration,
            snapshotID: snapshotID,
            recordedAt: recordedAt,
            historyLimit: historyLimit,
            to: try loadConfigurationHistory()
        )
        try save(history, fileName: FileName.configurationHistory)
    }

    func loadHandlerJournal() throws -> HandlerOperationJournal {
        try load(
            HandlerOperationJournal.self,
            fileName: FileName.handlerJournal
        )
    }

    func saveHandlerJournal(_ journal: HandlerOperationJournal) throws {
        try save(journal, fileName: FileName.handlerJournal)
    }

    func loadConfigurationHistory() throws -> ConfigurationHistory {
        try load(
            ConfigurationHistory.self,
            fileName: FileName.configurationHistory
        )
    }

    /// Read-only inspection for diagnostics and historical preview. Unlike
    /// recovery loads, these methods never quarantine or rewrite a file.
    func inspectHandlerJournal() throws -> HandlerOperationJournal {
        try inspect(
            HandlerOperationJournal.self,
            fileName: FileName.handlerJournal
        )
    }

    func inspectConfigurationHistory() throws -> ConfigurationHistory {
        try inspect(
            ConfigurationHistory.self,
            fileName: FileName.configurationHistory
        )
    }

    func inspectSchemaVersions() -> PersistedSchemaVersions {
        PersistedSchemaVersions(
            configuration: inspectSchemaVersion(
                fileName: FileName.configuration
            ),
            handlerJournal: inspectSchemaVersion(
                fileName: FileName.handlerJournal
            ),
            configurationHistory: inspectSchemaVersion(
                fileName: FileName.configurationHistory
            )
        )
    }

    func saveConfigurationHistory(_ history: ConfigurationHistory) throws {
        try save(history, fileName: FileName.configurationHistory)
    }

    private func appendingSnapshot(
        of configuration: RoutingConfiguration,
        snapshotID: UUID,
        recordedAt: Date,
        historyLimit: Int,
        to history: ConfigurationHistory
    ) -> ConfigurationHistory {
        var history = history
        let entry = ConfigurationHistoryEntry(
            id: snapshotID,
            recordedAt: recordedAt,
            configuration: configuration
        )
        if let index = history.entries.firstIndex(
            where: { $0.id == snapshotID }
        ) {
            history.entries[index] = entry
        } else {
            history.entries.append(entry)
        }
        let limit = max(0, historyLimit)
        if history.entries.count > limit {
            history.entries = Array(history.entries.suffix(limit))
        }
        return history
    }

    private func load<Value: VersionedPersistedState>(
        _ type: Value.Type,
        fileName: String
    ) throws -> Value {
        let fileURL = baseDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .fresh
        }

        do {
            let data = try Data(contentsOf: fileURL)
            try rejectFutureSchema(
                in: data,
                fileName: fileName,
                supported: Value.currentSchemaVersion
            )
            return try decoder.decode(Value.self, from: data)
        } catch let error as StateRepositoryError {
            throw error
        } catch {
            try quarantine(fileURL)
            return .fresh
        }
    }

    private func inspect<Value: VersionedPersistedState>(
        _ type: Value.Type,
        fileName: String
    ) throws -> Value {
        let fileURL = baseDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .fresh
        }
        let data = try Data(contentsOf: fileURL)
        try rejectFutureSchema(
            in: data,
            fileName: fileName,
            supported: Value.currentSchemaVersion
        )
        return try decoder.decode(Value.self, from: data)
    }

    private func inspectSchemaVersion(fileName: String) -> Int? {
        let fileURL = baseDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? decoder.decode(
            SchemaHeader.self,
            from: data
        ).schemaVersion
    }

    private func save<Value: VersionedPersistedState>(
        _ value: Value,
        fileName: String
    ) throws {
        guard value.schemaVersion <= Value.currentSchemaVersion else {
            throw StateRepositoryError.unsupportedSchema(
                fileName: fileName,
                found: value.schemaVersion,
                supported: Value.currentSchemaVersion
            )
        }

        let fileURL = baseDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let existing = try Data(contentsOf: fileURL)
                try rejectFutureSchema(
                    in: existing,
                    fileName: fileName,
                    supported: Value.currentSchemaVersion
                )
            } catch let error as StateRepositoryError {
                throw error
            } catch {
                try quarantine(fileURL)
            }
        }

        try fileManager.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(value)
        // Foundation implements .atomic with a sibling temporary file followed
        // by replacement, so readers never observe a partial JSON document.
        try data.write(to: fileURL, options: .atomic)
    }

    private func rejectFutureSchema(
        in data: Data,
        fileName: String,
        supported: Int
    ) throws {
        let header = try decoder.decode(SchemaHeader.self, from: data)
        guard header.schemaVersion <= supported else {
            throw StateRepositoryError.unsupportedSchema(
                fileName: fileName,
                found: header.schemaVersion,
                supported: supported
            )
        }
    }

    private func quarantine(_ fileURL: URL) throws {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension
        let quarantineName = "\(stem).corrupt-\(UUID().uuidString).\(fileExtension)"
        let quarantineURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(quarantineName)
        try fileManager.moveItem(at: fileURL, to: quarantineURL)
    }
}

private struct SchemaHeader: Decodable {
    var schemaVersion: Int
}
