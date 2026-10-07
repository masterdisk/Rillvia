import Foundation

struct BundleFacts: Equatable, Sendable {
    var bundleID: String
    var name: String
    var version: String
    var iconURL: URL = URL(fileURLWithPath: "/")
    var urlTypes: [[String]] = []
}

struct InstalledBrowser: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var version: String
    var appURL: URL
    var iconURL: URL = URL(fileURLWithPath: "/")
    var isImaginary: Bool = false
}

enum BrowserOrder {
    static func shelf(_ browsers: [InstalledBrowser], defaultID: String?) -> [InstalledBrowser] {
        browsers.sorted { lhs, rhs in
            if lhs.isImaginary != rhs.isImaginary {
                return !lhs.isImaginary
            }
            let lhsDefault = lhs.id == defaultID
            let rhsDefault = rhs.id == defaultID
            if lhsDefault != rhsDefault {
                return lhsDefault
            }
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if order == .orderedSame {
                return lhs.id < rhs.id
            }
            return order == .orderedAscending
        }
    }
}

enum BrowserDirectory {
    /// Browsers are apps that claim both schemes. When the http list is empty, the https list is used on its own so a lookup failure does not blank the shelf.
    static func assemble(
        https: [URL],
        http: [URL],
        facts: (URL) -> BundleFacts?,
        excluding: String? = nil
    ) -> [InstalledBrowser] {
        let httpIDs = Set(http.compactMap { facts($0)?.bundleID })
        let allowed: Set<String>? = httpIDs.isEmpty ? nil : httpIDs
        return collect(urls: https, facts: facts, excluding: excluding, allowed: allowed)
            .sorted { lhs, rhs in
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if order == .orderedSame { return lhs.id < rhs.id }
                return order == .orderedAscending
            }
    }

    static func isChooser(_ facts: BundleFacts) -> Bool {
        let identifier = facts.bundleID.lowercased()
        let name = facts.name.lowercased()
        if identifier.contains("browserswitch") || identifier.contains("browser-switch") {
            return true
        }
        return name == "browser switch" || name == "browserswitch"
    }

    static func isHelper(_ facts: BundleFacts) -> Bool {
        let identifier = facts.bundleID.lowercased()
        if identifier.contains("helper") {
            return true
        }
        return facts.name.lowercased().contains("helper")
    }

    /// A browser has an http/https type that is only web schemes. Terminals that also claim ssh, and apps that mix a private scheme into that same type, are left out.
    static func isBrowser(_ facts: BundleFacts) -> Bool {
        let web: Set<String> = ["http", "https", "file"]
        let terminal: Set<String> = ["ssh", "telnet", "ftp", "gopher"]
        let types = facts.urlTypes.map { type in Set(type.map { $0.lowercased() }) }
        let all = types.reduce(into: Set<String>()) { $0.formUnion($1) }
        if !all.isDisjoint(with: terminal) {
            return false
        }
        let hasWebType = types.contains { type in
            (type.contains("http") || type.contains("https")) && type.isSubset(of: web)
        }
        return hasWebType && all.contains("http") && all.contains("https")
    }

    private static func collect(
        urls: [URL],
        facts: (URL) -> BundleFacts?,
        excluding: String?,
        allowed: Set<String>?
    ) -> [InstalledBrowser] {
        var seen = Set<String>()
        var result: [InstalledBrowser] = []
        for url in urls {
            guard let info = facts(url) else { continue }
            if info.bundleID == excluding { continue }
            if isHelper(info) || isChooser(info) { continue }
            if !isBrowser(info) { continue }
            if let allowed, !allowed.contains(info.bundleID) { continue }
            if !seen.insert(info.bundleID).inserted { continue }
            result.append(
                InstalledBrowser(
                    id: info.bundleID,
                    name: info.name,
                    version: info.version,
                    appURL: url,
                    iconURL: info.iconURL
                )
            )
        }
        return result
    }
}
