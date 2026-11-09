<h1 align="center">
  <img src="Rillvia/Assets.xcassets/AppIcon.appiconset/AppIcon-128.png" alt="Rillvia app icon" width="64" height="64" align="middle">
  Rillvia
</h1>

<p align="center">
  <strong>Your links, your way.</strong><br>
  Work in Chrome. Read in Safari. Let each link find its browser.
</p>

<p align="center">
  <sub>A native macOS menu bar app · macOS 26+ · Apple silicon and Intel · Free and open source</sub>
</p>

<p align="center">
  <a href="https://github.com/masterdisk/Rillvia/releases/latest"><img src="https://img.shields.io/github/v/release/masterdisk/Rillvia?label=download&color=0062d2" alt="Latest release"></a>
  <a href="https://github.com/masterdisk/Rillvia/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/masterdisk/Rillvia/build.yml?branch=main&label=build" alt="Build status"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-555" alt="macOS 26 or later">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/masterdisk/Rillvia?color=555" alt="GPL-3.0 licence"></a>
</p>

<p align="center">
  <strong><a href="https://github.com/masterdisk/Rillvia/releases/latest">Download Rillvia</a></strong> &nbsp;·&nbsp;
  <a href="#get-rillvia">Install</a> &nbsp;·&nbsp;
  <a href="#a-small-menu-for-everyday-changes">See how it works</a> &nbsp;·&nbsp;
  <a href="#your-keys-your-actions">Keyboard shortcuts</a> &nbsp;·&nbsp;
  <a href="#questions">Questions</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/overview-dark.png">
    <img src="docs/images/overview-light.png" alt="Rillvia Overview with Safari for other links, Work rules active, and a GitHub link routed to Google Chrome" width="940">
  </picture>
</p>

<p align="center">
  <sub>Native app captures with sample rules.</sub>
</p>

## Get Rillvia

**macOS 26 or later.** One universal app for Apple silicon and Intel Macs.

1. Download **Rillvia-…-universal.dmg** from the [latest release](https://github.com/masterdisk/Rillvia/releases/latest).
2. Open the DMG and drag **Rillvia** into **Applications**.
3. Open Rillvia. The first time, macOS says it can't check the app for malicious software, because Rillvia isn't notarized by Apple yet. Click **Done**, then open **System Settings → Privacy & Security**, scroll to **Security** and click **Open Anyway** next to Rillvia.
4. Follow the short setup tour. Choose a browser for **Other links**, then **Turn on rules**. macOS asks whether to make Rillvia your default browser: choose **Use “Rillvia”**.

That's it. Add a rule for a site you use for work and click a link to try it. Later versions install from **Settings → Updates**.

<details>
  <summary><strong>Prefer Terminal for step 3?</strong></summary>

After dragging Rillvia into Applications, this removes the download flag macOS checks:

```sh
xattr -dr com.apple.quarantine /Applications/Rillvia.app
```

Each release lists the DMG's SHA-256 checksum. Compare it with `shasum -a 256 ~/Downloads/Rillvia-*-universal.dmg` before installing.

</details>

<details>
  <summary><strong>Build from source</strong></summary>

Use **Xcode with the macOS 26 SDK or newer**:

```sh
git clone https://github.com/masterdisk/Rillvia.git
cd Rillvia
open Rillvia.xcodeproj
```

Select the **Rillvia** scheme and run with **⌘R**. [Build, test, and run with sample data](docs/DEVELOPMENT.md).

</details>

## A small menu for everyday changes

Choose the browser for each site once. Rillvia uses those rules when you click a link.

- **Keep work and personal links separate.** Switch rule sets from the menu bar. Shared rules apply across sets.
- **Use one browser for a while.** Pick 15, 30, or 60 minutes, or until you stop. Your rules resume when the temporary choice ends.
- **Edit when you need to.** Open the workspace to change rules, review your browsers, or adjust settings.

<p align="center">
  <a href="docs/images/menu-bar.png"><img src="docs/images/menu-bar.png" alt="Rillvia menu bar panel with the active rule-set picker and a staged 15-minute Google Chrome choice" width="400"></a>
</p>

## Preview before you open

Paste a link to see its browser and the rule that matched. Preview reads your local rules without contacting the site or opening the link.

<p align="center">
  <a href="docs/images/preview.png"><img src="docs/images/preview.png" alt="Link preview showing a GitHub URL matched to Google Chrome by the Work rule set" width="940"></a>
</p>

## Your keys, your actions

Switch browsers, change rule sets, or preview a copied link without reaching for the menu. Custom shortcuts can work **Everywhere**, even while another app is active, as long as Rillvia is running.

In **Settings → Keyboard shortcuts → Add shortcut**, record your keys, choose an action, and save. Choose **In Rillvia** for an app-only shortcut.

Examples you can configure:

| Keys | Action |
| --- | --- |
| <kbd>⌃⌥⇧C</kbd> | Use Google Chrome for links |
| <kbd>⌃⌥P</kbd> | Switch to your Personal rule set |

<p align="center">
  <a href="docs/images/shortcut-builder.png"><img src="docs/images/shortcut-builder.png" alt="Shortcut builder assigning Control-Option-Shift-C to Google Chrome with Everywhere scope selected" width="940"></a>
</p>

<details>
  <summary><strong>Shortcut actions and built-in keys</strong></summary>

Custom actions include choosing a browser, starting or ending a temporary browser, switching or cycling rule sets, opening Rillvia, and previewing a copied web link. With rules configured, **Use a browser for links** changes the saved **Other links** choice. In direct mode, it changes the macOS default browser.

Saved shortcuts can be edited, disabled, or deleted with Undo. Custom shortcuts pause while the editor is open. The editor rejects ordinary typing, reserved app commands, and duplicate keys. If macOS cannot register a global shortcut, choose another combination.

These built-in keys work while Rillvia is active:

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

Inside text fields, **⌘Z** undoes typing. In pickers, arrows move, **Return** chooses, and **Esc** cancels.

Custom keyboard actions are separate from Apple Shortcuts automation, which has its own permission in Settings.

</details>

## Set it up, then make it yours

- **Save changes when you're ready.** Undo rule deletions and inspect earlier configurations without replacing your current rules.
- **Read it comfortably.** Choose light, dark, or system appearance and increase text to 200%.
- **Start with your Mac.** Turn on open at login in Settings. Replay the setup tour from **Settings → Help → Start tutorial**.
- **Update when it suits you.** Check in **Settings → Updates**. Download first, then choose **Install and restart** and confirm. Your rules and shortcuts carry over.

<details>
  <summary><strong>See the rule editor, browsers, and setup tour</strong></summary>

### Give each site a home

Choose a browser for a domain, keep the rule shared or in a set, and save when you're ready.

<p align="center">
  <a href="docs/images/rules.png"><img src="docs/images/rules.png" alt="Rule editor assigning github.com to Google Chrome in the Work rule set" width="940"></a>
</p>

### Your installed browsers

Review available browsers and their accounts before choosing where links should open.

<p align="center">
  <a href="docs/images/browsers.png"><img src="docs/images/browsers.png" alt="Browser collection with Google Chrome selected and Safari set for other links" width="940"></a>
</p>

### A short first-run tour

Review your browsers, add a rule, and try your first link preview. You can replay the tour later.

<p align="center">
  <a href="docs/images/tutorial.png"><img src="docs/images/tutorial.png" alt="First step of Rillvia's five-step setup tour in its main window" width="940"></a>
</p>

</details>

<details>
  <summary><strong>How Rillvia chooses a browser</strong></summary>

With rules on, Rillvia chooses in this order:

1. Your temporary browser, if one is active.
2. A matching rule in the active set.
3. A matching shared rule.
4. The browser chosen for **Other links**.

Turning rules off restores an external browser as the macOS handler. Rillvia also respects later default-browser changes made in macOS: rules pause, and **Turn on rules** resumes them. A link that still reaches Rillvia while rules are off or paused opens in the browser macOS uses.

Opening or copying a link preserves the original URL. Private-window choices apply to an individual open and are not silently saved as ordinary rules.

</details>

## Private by design

Rillvia runs entirely on your Mac. It never sends, logs or stores the links you open; it decides where each one goes and hands it to that browser. There are no accounts, analytics or background connections. The only network request is the update check you start yourself, which asks GitHub for the latest release.

## Questions

<details>
  <summary><strong>Why does macOS ask before Rillvia opens links?</strong></summary>

To route links, Rillvia becomes the default web browser while rules are on, and macOS always confirms that change. Rillvia then passes every link straight to the browser your rules choose.

</details>

<details>
  <summary><strong>How do I go back to my usual browser, or remove Rillvia?</strong></summary>

Choose **Settings → Turn off rules**. Rillvia hands links back to your Other links browser, or keeps the browser macOS already uses. Then quit Rillvia from the menu bar and move it to the Bin. Saved rules live in `~/Library/Application Support/Rillvia` if you want to remove them too.

</details>

<details>
  <summary><strong>What if I change the default browser in System Settings?</strong></summary>

Rillvia respects it and pauses your rules. Links go to the browser you picked. **Turn on rules** in Rillvia resumes them whenever you like.

</details>

<details>
  <summary><strong>Does it work with Chrome profiles and private windows?</strong></summary>

Yes. Rules can open a site in a specific Chrome, Edge, Brave, Vivaldi, Opera, Dia or Firefox profile, and previewed links can open in a private window, even when that browser is already running.

</details>

<details>
  <summary><strong>Why isn't it notarized?</strong></summary>

Notarization needs a paid Apple Developer account. The release workflow already supports Developer ID signing and notarization, and will use it once that account is set up. Until then, the source is here to read and build yourself.

</details>

## Contributing

Bug reports, ideas and pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md). Please include the text from **Settings → Help → Diagnostics → Copy Redacted Snapshot** with bug reports; it contains no links or browsing data.

Built with **Swift and SwiftUI**. [Build and test](docs/DEVELOPMENT.md) &nbsp;·&nbsp; [DMG builds, CI and updates](docs/DISTRIBUTION.md) &nbsp;·&nbsp; [Changelog](CHANGELOG.md)

## Licence

Rillvia is free software under the [GNU General Public License v3.0](LICENSE). You can use, study, share and change it; versions you distribute must stay under the same licence.

---

<p align="center">
  <sub><strong>Rillvia</strong> joins <em>rill</em>, a small stream, with <em>via</em>, a route.</sub>
</p>
