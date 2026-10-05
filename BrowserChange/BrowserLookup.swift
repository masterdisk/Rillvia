import AppKit
import Foundation

enum ProbeURL {
    static let https = URL(string: "https://example.com")!
    static let http = URL(string: "http://example.com")!
}

enum ContainingApp {
    /// The .app that contains this one, when a handler lives inside another app's bundle.
    static func hostApplication(for url: URL) -> URL? {
        var current = url.deletingLastPathComponent()
        var found: URL?
        while current.path != "/" {
            if current.pathExtension == "app" {
                found = current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return found
    }
}

enum BrowserLocation {
    static func isUserFacing(_ url: URL) -> Bool {
        let path = url.path
        let blocked = [
            "/Library/Caches/",
            "/.cache/",
            "/ms-playwright/",
            "/.agent-browser/",
            "/codex-runtimes/",
            "/node_modules/",
        ]
        return !blocked.contains { path.contains($0) }
    }
}

enum BundleReader {
    static func facts(at url: URL) -> BundleFacts? {
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
            return nil
        }
        let hostURL = ContainingApp.hostApplication(for: url)
        let presented = hostURL.flatMap(Bundle.init(url:)) ?? bundle
        let presentedPath = hostURL ?? url
        let displayName = presented.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = presented.object(forInfoDictionaryKey: "CFBundleName") as? String
        let name = displayName ?? bundleName ?? FileManager.default.displayName(atPath: presentedPath.path)
        let version = shortVersion(of: presented) ?? shortVersion(of: bundle) ?? "No version listed"
        return BundleFacts(
            bundleID: identifier,
            name: name,
            version: version,
            iconURL: presentedPath,
            urlTypes: urlTypes(of: bundle)
        )
    }

    private static func shortVersion(of bundle: Bundle) -> String? {
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return shortVersion ?? buildVersion
    }

    private static func urlTypes(of bundle: Bundle) -> [[String]] {
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.compactMap { type in
            type["CFBundleURLSchemes"] as? [String]
        }
    }
}

enum BrowserLookup {
    static func installedBrowsers() -> [InstalledBrowser] {
        let workspace = NSWorkspace.shared
        let found = BrowserDirectory.assemble(
            https: workspace.urlsForApplications(toOpen: ProbeURL.https),
            http: workspace.urlsForApplications(toOpen: ProbeURL.http),
            facts: BundleReader.facts(at:),
            excluding: Bundle.main.bundleIdentifier
        )
        let defaultID = defaultBundleID()
        return found.filter { browser in
            browser.id == defaultID || BrowserLocation.isUserFacing(browser.appURL)
        }
    }

    static func defaultBundleID() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: ProbeURL.https) else {
            return nil
        }
        return Bundle(url: url)?.bundleIdentifier
    }
}
