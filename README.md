<p align="center">
  <img src="assets/branding/rillvia/app-icon.png" alt="Rillvia app icon" width="112" height="112">
</p>

<h1 align="center">Rillvia</h1>

<p align="center">
  <strong>Your links, your way.</strong><br>
  A native macOS menu bar app that opens each link in the browser you choose.
</p>

<p align="center">
  <a href="#getting-started"><img src="https://img.shields.io/badge/macOS-26%2B-24292f?style=flat-square&amp;logo=apple&amp;logoColor=white" alt="Requires macOS 26 or later"></a>
  <img src="https://img.shields.io/badge/SwiftUI-Native-007AFF?style=flat-square&amp;logo=swift&amp;logoColor=white" alt="Native SwiftUI app">
</p>

<p align="center">
  <a href="#features">Features</a> &nbsp;·&nbsp;
  <a href="#screenshots">Screenshots</a> &nbsp;·&nbsp;
  <a href="#getting-started">Get started</a> &nbsp;·&nbsp;
  <a href="#keyboard-shortcuts">Keyboard shortcuts</a> &nbsp;·&nbsp;
  <a href="https://github.com/masterdisk/Rillvia/releases">Releases</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/overview-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/overview-light.png">
    <img src="docs/images/overview-light.png" alt="Rillvia Overview: Safari for other links, Work rules active, and a GitHub link previewed in Google Chrome" width="940">
  </picture>
</p>

<p align="center"><sub>Native app screenshots with sample rules. The overview follows your browser's light or dark appearance.</sub></p>

## Features

Use Chrome for work, Safari for reading, and a separate browser for personal links. Choose the browser for each site once; Rillvia handles the next link you click.

| | What you can do |
| --- | --- |
| **Rules for each site** | Send a domain to the browser you choose. Use shared rules for sites that should always open the same way. |
| **Work and Personal sets** | Keep different rules for different parts of your day. Switch the active set right from the menu bar. |
| **Preview before opening** | See which browser will open a link and which rule matched. The preview stays local and leaves the link unopened. |
| **One browser for a while** | Use a browser for 15, 30, or 60 minutes, or until you stop. Your rules resume when the temporary choice ends. |
| **Custom shortcuts** | Record keys for browsers, rule sets, temporary switches, and clipboard previews. They can work from any app. |
| **Undo and history** | Save rule edits when you're ready. Undo deletions and inspect earlier configurations without changing your current rules. |
| **Updates on your terms** | Check for a new version in Settings. Download it first, then choose when to install and restart. |
| **Readable controls** | Increase text to 200%. Keyboard focus stays visible, and glass controls follow Reduce Transparency. |

The daily controls live in the menu bar. Open the workspace when you want to edit rules, preview a link, or change settings. Light and dark appearances, native glass controls, and keyboard navigation keep it at home on your Mac.

## Screenshots

<table>
  <tr>
    <td width="50%" valign="top">
      <strong>Know where a link will go</strong><br>
      <sub>The browser, the matching rule, and notes about the URL.</sub><br><br>
      <a href="docs/images/preview.png"><img src="docs/images/preview.png" alt="Link preview showing a GitHub URL routed to Google Chrome by the Work rule set" width="460"></a>
    </td>
    <td width="50%" valign="top">
      <strong>Give each site a home</strong><br>
      <sub>Shared rules, separate sets, and an explicit Save.</sub><br><br>
      <a href="docs/images/rules.png"><img src="docs/images/rules.png" alt="Rule editor assigning github.com to Google Chrome in the Work rule set" width="460"></a>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>A small menu for everyday changes</strong><br>
      <sub>Switch rule sets or use one browser temporarily.</sub><br><br>
      <a href="docs/images/menu-bar.png"><img src="docs/images/menu-bar.png" alt="Rillvia menu bar panel with the active rule-set picker and a staged 15-minute Chrome choice" width="400"></a>
    </td>
    <td width="50%" valign="top">
      <strong>Your keys, your actions</strong><br>
      <sub>Record a combination, choose an action, and save.</sub><br><br>
      <a href="docs/images/shortcut-builder.png"><img src="docs/images/shortcut-builder.png" alt="Shortcut builder with Control-Option-Shift-C assigned to Google Chrome and Everywhere scope selected" width="460"></a>
    </td>
  </tr>
</table>

<details>
  <summary>See the browser collection and setup tour</summary>

<table>
  <tr>
    <td width="50%" valign="top">
      <strong>Your installed browsers</strong><br>
      <sub>Choose a browser and see its available accounts.</sub><br><br>
      <a href="docs/images/browsers.png"><img src="docs/images/browsers.png" alt="Browser collection with Google Chrome selected and Safari set for other links" width="460"></a>
    </td>
    <td width="50%" valign="top">
      <strong>A short first-run tour</strong><br>
      <sub>Review your browsers, rules, and first link preview.</sub><br><br>
      <a href="docs/images/tutorial.png"><img src="docs/images/tutorial.png" alt="First step of Rillvia's five-step setup tour" width="460"></a>
    </td>
  </tr>
</table>

</details>

## Getting started

Requires **macOS 26 or later**. Get a DMG from a published [release](https://github.com/masterdisk/Rillvia/releases) or a successful [GitHub build](https://github.com/masterdisk/Rillvia/actions/workflows/build.yml). Drag Rillvia to Applications, open it, and follow the setup tour.

To build the current code yourself, use **Xcode with the macOS 26 SDK or newer**:

```sh
git clone https://github.com/masterdisk/Rillvia.git
cd Rillvia
open Rillvia.xcodeproj
```

1. Select the **Rillvia** scheme in Xcode and run it with **⌘R**.
2. Follow the setup tour. Pick a browser for **Other links**, then turn on rules when you're ready.
3. Add a site in **Rules** and choose its browser. Paste a link into **Preview a link** to check the result.
4. Close the main window and use Rillvia from the menu bar. Switch sets there whenever your day changes.

Replay the tour at any time in **Settings → Help → Start tutorial**. Settings also includes appearance, text size, and open-at-login choices.

**Settings → Updates** checks for new versions when you ask. Downloads are verified, then wait for **Install and restart**. Your saved rules and shortcuts carry over. For private releases, sign in with GitHub CLI or use **Open Releases**. [Builds and update setup](docs/DISTRIBUTION.md)

## Keyboard shortcuts

Go to **Settings → Keyboard shortcuts → Add shortcut**. Record keys with **⌘** or **⌃**, pick an action, and choose its browser, duration, or rule set.

**Everywhere** works while another app is active and Rillvia's window is closed, as long as Rillvia is running. Choose **In Rillvia** for an app-only shortcut. Custom shortcuts pause while the editor is open; saved shortcuts can be edited, disabled, or deleted with Undo.

Examples you can configure:

| Keys | Action |
| --- | --- |
| <kbd>⌃⌥⇧C</kbd> | Use Google Chrome for links |
| <kbd>⌃⌥P</kbd> | Switch to your Personal rule set |

Actions also include starting or ending a temporary browser, cycling through rule sets, opening Rillvia, and previewing a copied web link. With rules configured, **Use a browser for links** changes the saved **Other links** choice. In direct mode, it changes the macOS default browser.

<details>
  <summary>Built-in keyboard reference</summary>

These keys work while Rillvia is active.

| Action | Keys |
| --- | --- |
| Overview / Preview / Rules / Browsers | <kbd>⌘1</kbd> / <kbd>⌘2</kbd> / <kbd>⌘3</kbd> / <kbd>⌘4</kbd> |
| Settings | <kbd>⌘,</kbd> |
| Focus link preview | <kbd>⌘L</kbd> |
| Choose browser for Other links | <kbd>⌘B</kbd> |
| Choose active rule set | <kbd>⇧⌘R</kbd> |
| Use a browser temporarily | <kbd>⌘T</kbd> |
| Search the current list | <kbd>⌘F</kbd> |
| New rule / Save rule | <kbd>⌘N</kbd> / <kbd>⌘S</kbd> |
| Preview focused input / Open current preview | <kbd>Return</kbd> / <kbd>⌘Return</kbd> |
| Undo a rule or rule-set change | <kbd>⌘Z</kbd> outside text fields |
| Keyboard shortcuts | <kbd>⌘/</kbd> |
| Diagnostics / Configuration history | <kbd>⌥⌘U</kbd> / <kbd>⌥⌘T</kbd> |

Inside text fields, **⌘Z** undoes typing. In pickers, arrows move, **Return** chooses, and **Esc** cancels. The editor rejects ordinary typing, reserved app commands, and duplicate keys. If macOS cannot register a global shortcut, choose another combination.

Custom keyboard actions are separate from Apple Shortcuts automation, which has its own permission in Settings.

</details>

## How links open

With rules on, Rillvia chooses in this order:

1. Your temporary browser, if one is active.
2. A matching rule in the active set.
3. A matching shared rule.
4. The browser chosen for **Other links**.

Turning rules off restores an external browser as the macOS handler. Rillvia also respects later default-browser changes made in macOS.

Preview reads the URL and your local rules without contacting the site. Opening or copying preserves the original URL. Private-window choices apply to an individual open and are not silently saved as ordinary rules.

## Development

Rillvia is built with **Swift and SwiftUI**. The project, scheme, and app are all named **Rillvia**; the bundle ID is `com.rillvia.app`.

- [Build, test, and run with sample data](docs/DEVELOPMENT.md)
- [DMG builds, CI, signing, and updates](docs/DISTRIBUTION.md)
- [Native design checks and verification results](design-qa.md)
- [Screenshot sources](docs/images/README.md)

---

<p align="center">
  <sub><strong>Rillvia</strong> joins <em>rill</em>, a small stream, with <em>via</em>, a route.</sub>
</p>
