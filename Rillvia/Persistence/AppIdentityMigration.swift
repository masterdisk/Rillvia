import Foundation

/// Previous identities are confined to upgrade support; normal reads and writes use Rillvia.
enum AppIdentityMigration {
    static let legacyBundleIdentifier = "com.browserchange.BrowserChange"
    static let legacySupportDirectoryName = "BrowserChange"
    private static let preferencesMarker = "rillviaIdentityMigration.v1"

    static func migratePreferences(to defaults: UserDefaults, legacyValues: [String: Any]) {
        guard !defaults.bool(forKey: preferencesMarker) else { return }
        for (key, value) in legacyValues where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: preferencesMarker)
    }

    static func migrateState(in applicationSupport: URL, appURL: URL, fileManager: FileManager = .default) throws -> URL {
        let destination = applicationSupport.appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw CocoaError(.fileWriteFileExists) }
            return destination
        }
        let source = applicationSupport.appendingPathComponent(legacySupportDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else { return destination }
        guard isDirectory.boolValue else { throw CocoaError(.fileReadCorruptFile) }

        let staging = applicationSupport.appendingPathComponent(".Rillvia-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: source.resolvingSymlinksInPath(), to: staging)
        for name in ["configuration.json", "handler-journal.json", "configuration-history.json"] {
            let file = staging.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: file.path) else { continue }
            let data = try Data(contentsOf: file)
            // Preserve unknown schemas and unreadable files for the repository's existing recovery rules.
            guard isSupported(data, name: name), let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            let migrated = replacingSelfReferences(in: json, appURL: appURL)
            let updated = try JSONSerialization.data(withJSONObject: migrated, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: file, options: .atomic)
        }
        try fileManager.moveItem(at: staging, to: destination)
        return destination
    }

    private static func isSupported(_ data: Data, name: String) -> Bool {
        let decoder = JSONDecoder()
        guard let schema = try? decoder.decode(SchemaHeader.self, from: data).schemaVersion else { return false }
        switch name {
        case "configuration.json":
            return schema <= RoutingConfiguration.currentSchemaVersion && (try? decoder.decode(RoutingConfiguration.self, from: data)) != nil
        case "handler-journal.json":
            return schema <= HandlerOperationJournal.currentSchemaVersion && (try? decoder.decode(HandlerOperationJournal.self, from: data)) != nil
        case "configuration-history.json":
            return schema <= ConfigurationHistory.currentSchemaVersion && (try? decoder.decode(ConfigurationHistory.self, from: data)) != nil
        default: return false
        }
    }

    private struct SchemaHeader: Decodable {
        var schemaVersion: Int
    }

    private static func replacingSelfReferences(in value: Any, appURL: URL) -> Any {
        if var object = value as? [String: Any] {
            if let browser = object["browser"] as? [String: Any], browser["bundleIdentifier"] as? String == legacyBundleIdentifier {
                object["applicationURL"] = appURL.absoluteString
            }
            if object["bundleIdentifier"] as? String == legacyBundleIdentifier {
                object["bundleIdentifier"] = AppIdentity.bundleIdentifier
            }
            return object.mapValues { replacingSelfReferences(in: $0, appURL: appURL) }
        }
        if let values = value as? [Any] { return values.map { replacingSelfReferences(in: $0, appURL: appURL) } }
        return value
    }
}
