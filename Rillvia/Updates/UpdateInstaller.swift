import AppKit
import Darwin
import Foundation
import Security

struct UpdateInstallPlan: Codable {
    var id: UUID
    var installedApp: URL
    var previousVersion: String
    var version: String
    var parentPID: Int32

    static var controlRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }
    var directory: URL { Self.controlRoot.appendingPathComponent("Install-\(id.uuidString)", isDirectory: true) }
    var manifest: URL { directory.appendingPathComponent("install.json") }
    var ready: URL { directory.appendingPathComponent("ready") }
    var launched: URL { directory.appendingPathComponent("launched") }
    var stagedApp: URL { sibling("update") }
    var backupApp: URL { sibling("previous") }
    private func sibling(_ name: String) -> URL {
        installedApp.deletingLastPathComponent().appendingPathComponent(".Rillvia-\(name)-\(id.uuidString).app", isDirectory: true)
    }
}

enum UpdateBundleValidation {
    static func validate(_ candidate: URL, version: String, installedApp: URL) throws {
        guard let bundle = Bundle(url: candidate), bundle.bundleIdentifier == AppIdentity.bundleIdentifier,
              let actual = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let actualVersion = ReleaseVersion(actual), let expectedVersion = ReleaseVersion(version),
              actualVersion == expectedVersion, bundle.executableURL != nil else { throw UpdateError.invalidApp }
        try UpdateTool.runSynchronously(URL(fileURLWithPath: "/usr/bin/codesign"), ["--verify", "--deep", "--strict", candidate.path])
        try validateTeam(installed: teamIdentifier(installedApp), candidate: teamIdentifier(candidate))
    }

    static func validateTeam(installed: String?, candidate: String?) throws {
        if let installed, candidate != installed { throw UpdateError.wrongSigner }
    }

    private static func teamIdentifier(_ app: URL) throws -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, SecCSFlags(), &code) == errSecSuccess, let code else { throw UpdateError.invalidApp }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else { throw UpdateError.invalidApp }
        return values[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

enum BundleReplacement {
    /// Both renames stay on the app's volume. A failed replacement or launch restores the previous bundle.
    static func perform(_ plan: UpdateInstallPlan, fileManager: FileManager = .default, launch: (URL) -> Bool) throws {
        guard plan.installedApp.lastPathComponent == "Rillvia.app",
              fileManager.fileExists(atPath: plan.stagedApp.path),
              !fileManager.fileExists(atPath: plan.backupApp.path) else { throw UpdateError.cannotReplace }
        try fileManager.moveItem(at: plan.installedApp, to: plan.backupApp)
        do {
            try fileManager.moveItem(at: plan.stagedApp, to: plan.installedApp)
        } catch {
            try fileManager.moveItem(at: plan.backupApp, to: plan.installedApp)
            throw UpdateError.cannotReplace
        }
        guard launch(plan.installedApp) else {
            try fileManager.moveItem(at: plan.installedApp, to: plan.stagedApp)
            try fileManager.moveItem(at: plan.backupApp, to: plan.installedApp)
            throw UpdateError.launchFailed
        }
        try? fileManager.removeItem(at: plan.backupApp)
    }
}

@MainActor
protocol UpdateInstalling {
    func install(_ diskImage: URL, release: UpdateRelease) async throws
}

@MainActor
struct MacUpdateInstaller: UpdateInstalling {
    func install(_ diskImage: URL, release: UpdateRelease) async throws {
        guard let asset = release.asset else { throw UpdateError.noInstaller }
        try UpdateFiles.verify(diskImage, asset: asset)
        let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard app.lastPathComponent == "Rillvia.app",
              FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path),
              let executable = Bundle.main.executableURL else { throw UpdateError.cannotReplace }
        let previous = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard let oldVersion = ReleaseVersion(previous), release.version > oldVersion else { throw UpdateError.invalidRelease }
        let plan = UpdateInstallPlan(id: UUID(), installedApp: app, previousVersion: previous,
            version: release.version.description, parentPID: ProcessInfo.processInfo.processIdentifier)
        let mount = try UpdateFiles.makeTemporaryDirectory()
        var attached = false
        var helper: Process?
        defer {
            if attached { try? UpdateTool.runSynchronously(URL(fileURLWithPath: "/usr/bin/hdiutil"), ["detach", mount.path]) }
            try? FileManager.default.removeItem(at: mount)
        }
        do {
            try await UpdateTool.run(URL(fileURLWithPath: "/usr/bin/hdiutil"),
                ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, diskImage.path])
            attached = true
            let candidate = mount.appendingPathComponent("Rillvia.app", isDirectory: true)
            try await Task.detached { try UpdateBundleValidation.validate(candidate, version: plan.version, installedApp: app) }.value
            try FileManager.default.copyItem(at: candidate, to: plan.stagedApp)
            try await Task.detached { try UpdateBundleValidation.validate(plan.stagedApp, version: plan.version, installedApp: app) }.value
            try FileManager.default.createDirectory(at: plan.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(plan).write(to: plan.manifest, options: .atomic)
            let process = Process()
            helper = process
            process.executableURL = executable
            process.arguments = ["--rillvia-install-update", plan.manifest.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            for _ in 0..<100 {
                if FileManager.default.fileExists(atPath: plan.ready.path) {
                    try await UpdateTool.run(URL(fileURLWithPath: "/usr/bin/hdiutil"), ["detach", mount.path])
                    attached = false
                    NSApp.terminate(nil)
                    return
                }
                guard process.isRunning else { throw UpdateError.cannotReplace }
                try await Task.sleep(for: .milliseconds(100))
            }
            process.terminate()
            throw UpdateError.timeout
        } catch {
            if let helper, helper.isRunning { helper.terminate() }
            try? FileManager.default.removeItem(at: plan.stagedApp)
            try? FileManager.default.removeItem(at: plan.directory)
            throw error
        }
    }
}

enum UpdateInstallerHelper {
    static func runIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let index = arguments.firstIndex(of: "--rillvia-install-update") else { return }
        do {
            guard arguments.indices.contains(index + 1) else { throw UpdateError.invalidApp }
            let plan = try readPlan(URL(fileURLWithPath: arguments[index + 1]))
            guard plan.installedApp == Bundle.main.bundleURL.resolvingSymlinksInPath(), plan.parentPID == getppid(),
                  Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == plan.previousVersion else { throw UpdateError.invalidApp }
            try UpdateBundleValidation.validate(plan.stagedApp, version: plan.version, installedApp: plan.installedApp)
            try Data().write(to: plan.ready, options: .atomic)
            let deadline = Date().addingTimeInterval(60)
            while kill(plan.parentPID, 0) == 0 {
                guard Date() < deadline else { throw UpdateError.timeout }
                usleep(100_000)
            }
            do {
                try BundleReplacement.perform(plan) { app in
                    do {
                        try UpdateTool.runSynchronously(URL(fileURLWithPath: "/usr/bin/open"),
                            ["-n", "-a", app.path, "--args", "--rillvia-finish-update", plan.manifest.path])
                        let deadline = Date().addingTimeInterval(25)
                        while Date() < deadline {
                            if FileManager.default.fileExists(atPath: plan.launched.path) { return true }
                            usleep(100_000)
                        }
                    } catch {}
                    return false
                }
            } catch {
                try? UpdateTool.runSynchronously(URL(fileURLWithPath: "/usr/bin/open"),
                    ["-n", "-a", plan.installedApp.path, "--args", "--rillvia-update-rolled-back"])
                throw error
            }
            try? FileManager.default.removeItem(at: plan.directory)
            exit(EXIT_SUCCESS)
        } catch { exit(EXIT_FAILURE) }
    }

    static func recordSuccessfulLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let index = arguments.firstIndex(of: "--rillvia-finish-update"), arguments.indices.contains(index + 1),
              let plan = try? readPlan(URL(fileURLWithPath: arguments[index + 1])),
              plan.installedApp == Bundle.main.bundleURL.resolvingSymlinksInPath(),
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              ReleaseVersion(version) == ReleaseVersion(plan.version) else { return }
        try? Data().write(to: plan.launched, options: .atomic)
    }

    private static func readPlan(_ url: URL) throws -> UpdateInstallPlan {
        let root = UpdateInstallPlan.controlRoot.resolvingSymlinksInPath().path + "/"
        guard url.resolvingSymlinksInPath().path.hasPrefix(root), url.lastPathComponent == "install.json" else { throw UpdateError.invalidApp }
        let plan = try JSONDecoder().decode(UpdateInstallPlan.self, from: Data(contentsOf: url))
        guard plan.manifest.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() else { throw UpdateError.invalidApp }
        return plan
    }
}
