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

The check results and their limits are recorded in [design-qa.md](../design-qa.md) and [the current review](../reviews/2026-10-07-accessibility/README.md). Actual macOS default-browser consent, browser account launches, login-item registration, and invocation from the Apple Shortcuts app are outside that automated run.

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

The approved studies and interaction specifications are in [reviews/2026-10-06-liquid-directions](../reviews/2026-10-06-liquid-directions). Native screenshots, comparisons, and review history are in [reviews/2026-10-06-rillvia-implementation](../reviews/2026-10-06-rillvia-implementation).

Original brand assets, prompts, and the limited name check are in [assets/branding/rillvia](../assets/branding/rillvia). Browser icons come from installed applications, and navigation icons use native system symbols.
