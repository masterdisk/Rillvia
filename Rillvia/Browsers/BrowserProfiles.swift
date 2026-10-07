import Foundation

enum BrowserProfileFamily: String, Codable, Hashable, Sendable {
    case chromium
    case firefox
}

struct BrowserProfileChoice: Codable, Hashable, Sendable, Identifiable {
    var key: String
    var name: String
    var family: BrowserProfileFamily

    var id: String {
        "\(family.rawValue)|\(key)"
    }
}

enum BrowserLaunchMode: Equatable, Hashable, Sendable {
    case standard
    case privateWindow
    case profile(BrowserProfileChoice)
}

protocol BrowserProfileReading: Sendable {
    func profiles(for bundleIdentifier: String) -> [BrowserProfileChoice]
    func supportsPrivateWindow(_ bundleIdentifier: String) -> Bool
}

struct EmptyBrowserProfileReader: BrowserProfileReading {
    func profiles(for bundleIdentifier: String) -> [BrowserProfileChoice] {
        []
    }

    func supportsPrivateWindow(_ bundleIdentifier: String) -> Bool {
        false
    }
}

struct SystemBrowserProfileReader: BrowserProfileReading {
    var home: URL
    var fileManager: FileManager

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.home = home
        self.fileManager = fileManager
    }

    func profiles(for bundleIdentifier: String) -> [BrowserProfileChoice] {
        if let relative = BrowserProfileCatalog.chromiumSupport[bundleIdentifier] {
            let url = home
                .appendingPathComponent("Library/Application Support")
                .appendingPathComponent(relative)
                .appendingPathComponent("Local State")
            guard let data = try? Data(contentsOf: url) else { return [] }
            return BrowserProfileCatalog.chromiumProfiles(from: data)
        }
        if let relative = BrowserProfileCatalog.firefoxSupport[bundleIdentifier] {
            let url = home
                .appendingPathComponent("Library/Application Support")
                .appendingPathComponent(relative)
                .appendingPathComponent("profiles.ini")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                return []
            }
            return BrowserProfileCatalog.firefoxProfiles(from: text)
        }
        return []
    }

    func supportsPrivateWindow(_ bundleIdentifier: String) -> Bool {
        BrowserProfileCatalog.supportsPrivateWindow(bundleIdentifier)
    }
}

enum BrowserProfileCatalog {
    static let chromiumSupport: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.operasoftware.Opera": "com.operasoftware.Opera",
        "org.chromium.Chromium": "Chromium",
        "company.thebrowser.dia": "Dia",
        "com.diatheapp.Dia": "Dia",
    ]

    static let firefoxSupport: [String: String] = [
        "org.mozilla.firefox": "Firefox",
        "org.mozilla.nightly": "Firefox",
        "org.mozilla.firefoxdeveloperedition": "Firefox",
    ]

    static func supportsPrivateWindow(_ bundleIdentifier: String) -> Bool {
        chromiumSupport[bundleIdentifier] != nil
            || firefoxSupport[bundleIdentifier] != nil
    }

    static func launchArguments(
        bundleIdentifier: String,
        launch: BrowserLaunchMode,
        url: URL
    ) -> [String] {
        switch launch {
        case .standard:
            []
        case .privateWindow:
            privateArguments(bundleIdentifier: bundleIdentifier, url: url)
        case .profile(let profile):
            profileArguments(profile, url: url)
        }
    }

    static func chromiumProfiles(from data: Data) -> [BrowserProfileChoice] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = root["profile"] as? [String: Any],
            let cache = profile["info_cache"] as? [String: Any]
        else {
            return []
        }

        return cache.compactMap { key, value in
            guard key == "Default" || key.hasPrefix("Profile ") else {
                return nil
            }
            let info = value as? [String: Any]
            let rawName = (info?["gaia_name"] as? String)
                ?? (info?["name"] as? String)
                ?? (info?["user_name"] as? String)
                ?? key
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            return BrowserProfileChoice(
                key: key,
                name: name.isEmpty ? key : name,
                family: .chromium
            )
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func firefoxProfiles(from text: String) -> [BrowserProfileChoice] {
        var profiles: [BrowserProfileChoice] = []
        var currentName: String?
        var isProfile = false

        func flush() {
            guard isProfile, let currentName else { return }
            let name = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            profiles.append(
                BrowserProfileChoice(
                    key: name,
                    name: name,
                    family: .firefox
                )
            )
        }

        for line in text.split(whereSeparator: \.isNewline) {
            let row = line.trimmingCharacters(in: .whitespaces)
            if row.hasPrefix("["), row.hasSuffix("]") {
                flush()
                currentName = nil
                isProfile = row.lowercased().hasPrefix("[profile")
                continue
            }
            if isProfile, row.lowercased().hasPrefix("name=") {
                currentName = String(row.dropFirst("name=".count))
            }
        }
        flush()

        var seen: Set<String> = []
        return profiles.filter { seen.insert($0.key).inserted }
    }

    private static func privateArguments(
        bundleIdentifier: String,
        url: URL
    ) -> [String] {
        if bundleIdentifier == "com.microsoft.edgemac" {
            return ["--inprivate", url.absoluteString]
        }
        if chromiumSupport[bundleIdentifier] != nil {
            return ["--incognito", url.absoluteString]
        }
        if firefoxSupport[bundleIdentifier] != nil {
            return ["-private-window", url.absoluteString]
        }
        return []
    }

    private static func profileArguments(
        _ profile: BrowserProfileChoice,
        url: URL
    ) -> [String] {
        switch profile.family {
        case .chromium:
            ["--profile-directory=\(profile.key)", url.absoluteString]
        case .firefox:
            ["-P", profile.key, url.absoluteString]
        }
    }
}
