# Developing Rillvia

Requires macOS 26 or later and Xcode with the macOS 26 SDK or newer. Open [Rillvia.xcodeproj](../Rillvia.xcodeproj) and select the **Rillvia** scheme. The built app is **Rillvia.app**.

## Build and run

From the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project Rillvia.xcodeproj -scheme Rillvia \
  -configuration Release -derivedDataPath build/RillviaDerivedData

open build/RillviaDerivedData/Build/Products/Release/Rillvia.app
```

If Xcode is installed elsewhere, adjust `DEVELOPER_DIR`. The project uses ad hoc signing for local builds and has no development team configured.

To package a universal installer, use `scripts/build-dmg.sh`. [Distribution](DISTRIBUTION.md) covers the DMG script, GitHub workflows, signing credentials, and the in-app update flow.

## Tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Rillvia.xcodeproj -scheme Rillvia \
  -destination 'platform=macOS' -derivedDataPath build/RillviaDerivedData \
  -parallel-testing-enabled NO
```

UI tests bring windows forward and interact with real native controls. They use temporary storage and fake browser handlers and launchers, so they leave your browser setup intact. The global-key test registers a real shortcut and invokes it with Calculator active and Rillvia's window closed.

To compile the app and tests without launching anything, replace `test` with `build-for-testing`. Add `-only-testing:RillviaTests` to run the unit suite without the interactive UI suite. GitHub builds run unit tests by default; the manual workflow offers UI tests separately.

Actual macOS default-browser consent, login-item registration and invocation from the Apple Shortcuts app are outside the automated tests.

### Checks beyond the test suite

Before 1.0.0, these ran against real system components:

- **Profile and private-window links:** Rillvia's `NSWorkspaceApplicationAccess.open` sent a `--profile-directory` link and an `--incognito` link to an already-running Chrome with an isolated `--user-data-dir`. Chrome's DevTools showed both tabs in that instance, the private one in its off-the-record context.
- **Update install:** ad hoc signed 1.0 and 1.1 bundles built from the real updater code. With the 1.1 disk image already mounted, as **Open installer** does, 1.0 installed 1.1 and it relaunched from the same path with no leftovers. A 1.1 that crashed on launch was rolled back to 1.0, relaunched with the launch-failed reason, and its hidden copy removed. On macOS 27.2, `hdiutil attach` warns that it is deprecated but still works.

## Sample configuration

Build the **Debug** configuration, then launch:

```sh
open -n build/RillviaDerivedData/Build/Products/Debug/Rillvia.app --args \
  --ui-testing --ui-testing-design-fixture --force-light-appearance
```

This starts an isolated sample with Safari, Dia, and Chrome, Work and Personal rule sets, and sample domain rules. It uses temporary storage and fake system handlers. Add `--ui-testing-menu-preview` for a standalone review window containing the actual menu component. That review path is disabled in Release.

For layout checks, add `--ui-testing-minimum-size`, `--ui-testing-large-text` (200%), `--ui-testing-reduce-transparency`, or `--ui-testing-increased-contrast`. These overrides affect the app's test environment and leave macOS preferences intact. Text size is also available in Settings for normal use.

## Naming and design

The project, scheme, module, and app are **Rillvia**. The bundle ID is `com.rillvia.app`, and saved state lives in `~/Library/Application Support/Rillvia`. The unit and UI targets are **RillviaTests** and **RillviaUITests**.

On the first launch after upgrading, Rillvia imports the previous app's preferences and saved state. Existing Rillvia data takes precedence. Rules, rule sets, history, temporary choices, and custom shortcuts carry over; the original files remain available as a backup. Compatibility identifiers are confined to `AppIdentityMigration.swift`. Tests use isolated storage and preferences.

After the identity change, quit the previous app and turn on rules in the new Rillvia app. macOS may ask you to confirm the new link handler. Imported settings alone do not grant the new bundle ID ownership of HTTP and HTTPS links.

Source artwork for the app icon and menu bar mark is in [assets/branding/rillvia](../assets/branding/rillvia). Browser icons come from installed applications, and navigation icons use native system symbols.
