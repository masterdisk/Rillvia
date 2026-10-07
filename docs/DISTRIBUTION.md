# Builds and updates

Rillvia packages as a universal DMG for Apple silicon and Intel Macs. The installer contains `Rillvia.app`, an Applications shortcut, and a short install guide.

## Build a DMG locally

From the repository root, with Xcode installed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  scripts/build-dmg.sh --version 1.0.0 --build 1
```

The result is `build/dist/Rillvia-1.0.0-universal.dmg`, alongside its SHA-256 checksum. The script builds both architectures, checks the app's bundle ID and signature, and verifies the disk image. Drag the app into Applications before using it.

Local builds use ad hoc signing. To use a Developer ID certificate already in your Keychain, set `RILLVIA_SIGNING_IDENTITY`. Set `RILLVIA_NOTARY_PROFILE` to a saved `notarytool` profile to submit the DMG to Apple and staple the accepted ticket. `RILLVIA_NOTARY_KEYCHAIN` selects a custom Keychain when needed.

## GitHub builds

[Build Rillvia](../.github/workflows/build.yml) runs on pushes to `main` and pull requests. It uses a macOS 26 runner, runs the unit tests, builds the universal app, and saves a DMG and checksum as workflow artifacts. Installers remain available for 14 days; test results remain for seven days.

You can also run the workflow manually. Its **Run native UI tests** option adds the full UI suite. That runner must be able to initialize Xcode's UI automation. The workflow does not change the runner's authorization settings.

## Prepare a release

[Prepare release](../.github/workflows/release.yml) runs when you push a version tag:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Use three numeric version components. The tagged commit must be on `main`. The workflow reruns the unit tests, packages that version, and creates a **draft** GitHub release with the DMG and checksum. Review it, then publish it when the build is ready for people to install. Drafts and prereleases are excluded from the app's update checks.

To sign releases, add these repository Actions secrets:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application certificate, exported with its private key. |
| `APPLE_CERTIFICATE_PASSWORD` | Password used for that `.p12` export. |
| `APPLE_SIGNING_IDENTITY` | Full certificate name, such as `Developer ID Application: Your Name (TEAMID)`. |

For notarization, also add `APPLE_ID`, `APPLE_APP_PASSWORD`, and `APPLE_TEAM_ID`. The workflow imports the certificate into a temporary Keychain, signs the app and DMG, submits the DMG, and staples an accepted ticket. It removes the temporary signing files at the end. Partial signing configuration stops the release job instead of producing an unintended unsigned build.

Without these credentials, the draft contains an ad hoc build and says it has not been notarized. The build workflow needs no signing secrets. Apple requires Developer ID signing for software submitted to its notarization service. [Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## Updates inside Rillvia

Choose **Settings → Updates → Check for updates**, or use the app menu or the menu bar's More options menu. Checks happen when you ask. Rillvia shows the available version, release notes, and the last successful check.

Choose **Download update** to fetch the DMG. Rillvia checks its size and GitHub's SHA-256 asset digest before offering installation. It then waits for you to choose **Install and restart** and confirm. Save or discard any rule draft first. **Later** leaves the download ready, and **Open installer** offers the normal drag-to-Applications path.

The installer checks the new app's bundle ID, version, and code signature. If the installed app has a Developer ID team, the update must have the same team. It stages the new app beside the installed copy, quits, replaces it, and relaunches. The previous copy stays available until the new app acknowledges a successful launch; a failed replacement or launch restores it. Saved rules and preferences remain in Application Support and UserDefaults.

The installed app's folder must be writable. Updates cannot replace a copy running inside a read-only DMG. No administrator password is stored or requested by Rillvia.

For a private repository, Rillvia uses the existing signed-in [GitHub CLI](https://cli.github.com/manual/gh_auth_login) at `/opt/homebrew/bin/gh` or `/usr/local/bin/gh`. It does not copy tokens into preferences, logs, the app, or release assets. If access is unavailable, it says so and offers **Open Releases**. A denied request is never reported as “up to date.” Public releases work without GitHub CLI.

Packaging follows [Apple's DMG instructions](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution). Asset integrity checks use [GitHub's release asset metadata](https://docs.github.com/en/rest/releases/assets).
