import Foundation

protocol BrowserCatalog {
    func installedBrowsers() -> [InstalledBrowser]
}

struct WorkspaceBrowserCatalog: BrowserCatalog {
    func installedBrowsers() -> [InstalledBrowser] {
        BrowserLookup.installedBrowsers()
    }
}

extension InstalledBrowser {
    var reference: BrowserReference {
        BrowserReference(bundleIdentifier: id)
    }
}
