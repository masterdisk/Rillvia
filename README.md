# Rillvia

A quiet macOS menu-bar app that sends each site to the browser you choose.

<img src="assets/branding/rillvia/app-icon.png" alt="Rillvia icon" width="128">

Choose a browser for other links, add rules for individual domains, and keep separate rule sets for Work, Personal, or anything else. Preview a link to see where it will open before opening it. Use one browser temporarily when you want a break from your rules.

The native interface includes Overview, Preview a link, Rules, Browsers, and Settings. Browser selection and rule-set browsing stay separate from changes to how links open. Rule edits save explicitly; deleting a rule or set offers Undo. The tour is available again in Settings.

Switch the active rule set directly from the menu bar. The picker lists your enabled sets and Shared rules only; Manage rule sets opens the workspace.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Overview / Preview / Rules / Browsers | ⌘1 / ⌘2 / ⌘3 / ⌘4 |
| Settings | ⌘, |
| Focus link preview | ⌘L |
| Choose browser for other links | ⌘B |
| Choose active rule set | ⇧⌘R |
| Use a browser temporarily | ⌘T |
| Search the current list | ⌘F |
| New rule / Save rule | ⌘N / ⌘S |
| Preview focused input / Open current preview | Return / ⌘Return |
| Undo a rule or rule-set change | ⌘Z outside text fields |
| Keyboard shortcuts | ⌘/ |
| Diagnostics / Configuration history | ⌥⌘U / ⌥⌘T |

These keys work while Rillvia is active. Native text editing keeps its usual Undo behavior. Pickers support arrows, Return, and Esc. Apple Shortcuts automation has a separate permission in Settings.

Add your own keys in **Settings → Keyboard shortcuts → Add shortcut**. Record a combination, choose an action, and select its browser, duration, or rule set. **Everywhere** works while another app is active and Rillvia's window is closed, as long as Rillvia is running. Choose **In Rillvia** to keep a shortcut inside the app. Your shortcuts pause while the editor is open.

Actions include choosing a browser for links, starting or ending a temporary browser, switching to a specific rule set, cycling through sets, opening Rillvia, and previewing a copied web link. With rules configured, the browser action updates the saved **Other links** choice. In direct mode, it changes the macOS default browser. Switching sets preserves your shared rules and unfinished rule drafts.

Saved shortcuts can be edited, disabled, or deleted with Undo. The editor rejects ordinary typing, reserved app commands, and duplicate keys. If macOS cannot register a global shortcut, choose another combination. Custom keyboard actions do not need the Apple Shortcuts automation permission.

## How links open

A temporary browser takes priority. Otherwise, a matching rule in the active set wins over a shared rule. When no usable rule matches, the browser selected for other links opens the URL. Turning rules off restores an external browser as the macOS handler. Rillvia respects later changes made in macOS rather than taking control back automatically.

Preview parses URLs and checks local configuration. It does not open or fetch them, scan a destination, or save previewed URLs to configuration history. URL notes describe the URL’s structure. Opening and copying a link preserve its original URL. Private-window choices apply to an individual open and are not silently saved as ordinary rules.

## Build and test

Requires macOS 26 or later and Xcode with the macOS SDK. Open `BrowserChange.xcodeproj` and use the **BrowserChange** scheme. The built app is **Rillvia.app**; the existing bundle ID and storage schema remain compatible with earlier versions.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project BrowserChange.xcodeproj -scheme BrowserChange \
  -configuration Release -derivedDataPath build/DerivedData

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project BrowserChange.xcodeproj -scheme BrowserChange \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData
```

UI tests use temporary storage and fake browser handlers and launchers. To inspect the sample configuration without changing your browser setup, launch a Debug build with `--ui-testing --ui-testing-design-fixture`.

For a standalone capture of the actual menu component, add `--ui-testing-menu-preview`. This review mode is disabled in Release. Final check results, native screenshots, and verification boundaries are recorded in `design-qa.md`.

## Design and branding

The approved screen studies and interaction specifications are in `reviews/2026-10-06-liquid-directions/`. Native implementation evidence and the comparison history are recorded in `design-qa.md`.

**Rillvia** combines *rill*, a small stream, with *via*, a route. The branching blue mark follows that idea. Original generated assets, prompts, and the limited public name check are in `assets/branding/rillvia/`. Application icons come from installed browsers; navigation and rule icons use native system symbols.
