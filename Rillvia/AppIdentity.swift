import Foundation

enum AppIdentity {
    static let bundleIdentifier = "com.rillvia.app"
    static let supportDirectoryName = "Rillvia"

    static func isSelf(_ browser: BrowserReference, reference: BrowserReference) -> Bool {
        browser == reference || browser.bundleIdentifier == bundleIdentifier
            || browser.bundleIdentifier == AppIdentityMigration.legacyBundleIdentifier
    }
}
