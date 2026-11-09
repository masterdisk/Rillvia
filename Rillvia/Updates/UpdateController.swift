import Foundation
import Observation

enum UpdatePhase: Equatable {
    case idle, checking, current, noRelease
    case available(UpdateRelease), downloading(UpdateRelease), ready(UpdateRelease, URL), installing
    case failed(String)
    var isBusy: Bool {
        switch self { case .checking, .downloading, .installing: true; default: false }
    }
}

@MainActor
@Observable
final class UpdateController {
    private(set) var phase: UpdatePhase = .idle
    private(set) var lastChecked: Date?
    private(set) var downloadedInstaller: URL?
    let installedVersion: String
    @ObservationIgnored private let client: any UpdateProviding
    @ObservationIgnored private let installer: any UpdateInstalling
    @ObservationIgnored private let defaults: UserDefaults

    init(client: any UpdateProviding, installer: any UpdateInstalling, defaults: UserDefaults,
         installedVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") {
        self.client = client
        self.installer = installer
        self.defaults = defaults
        self.installedVersion = installedVersion
        let timestamp = defaults.double(forKey: "updates.lastChecked")
        if timestamp > 0 { lastChecked = Date(timeIntervalSince1970: timestamp) }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--rillvia-update-rolled-back") {
            let notReplaced = arguments.indices.contains(index + 1) && arguments[index + 1] == "not-replaced"
            phase = .failed((notReplaced ? UpdateError.cannotReplace : UpdateError.launchFailed).localizedDescription)
        }
    }

    func check() async {
        guard !phase.isBusy else { return }
        phase = .checking
        do {
            let release = try await client.latestRelease()
            lastChecked = .now
            defaults.set(lastChecked!.timeIntervalSince1970, forKey: "updates.lastChecked")
            guard let release else { phase = .noRelease; return }
            guard let current = ReleaseVersion(installedVersion) else { throw UpdateError.invalidApp }
            phase = release.version > current ? .available(release) : .current
        } catch { phase = .failed(error.localizedDescription) }
    }

    func download() async {
        guard case .available(let release) = phase else { return }
        phase = .downloading(release)
        do {
            let file = try await client.download(release)
            downloadedInstaller = file
            phase = .ready(release, file)
        }
        catch { phase = .failed(error.localizedDescription) }
    }

    func installAndRestart() async {
        guard case .ready(let release, let file) = phase else { return }
        phase = .installing
        do { try await installer.install(file, release: release) }
        catch { phase = .failed(error.localizedDescription) }
    }

    static func bootstrap(arguments: [String] = ProcessInfo.processInfo.arguments) -> UpdateController {
        #if DEBUG
        if arguments.contains("--ui-testing") || NSClassFromString("XCTestCase") != nil {
            return UpdateController(client: FixtureUpdateClient(available: arguments.contains("--ui-testing-update-available"),
                downloadable: arguments.contains("--ui-testing-update-downloadable")),
                installer: FixtureUpdateInstaller(), defaults: AppPreferences.defaults)
        }
        #endif
        return UpdateController(client: GitHubUpdateClient(), installer: MacUpdateInstaller(), defaults: AppPreferences.defaults)
    }
}

#if DEBUG
private struct FixtureUpdateClient: UpdateProviding {
    var available: Bool
    var downloadable: Bool
    func latestRelease() async throws -> UpdateRelease? {
        guard available else { return nil }
        let asset = downloadable ? UpdateAsset(id: 1, name: "Rillvia-99.0.0-universal.dmg", size: 16,
            sha256: String(repeating: "a", count: 64), downloadURL: UpdateSource.releasesURL) : nil
        return UpdateRelease(version: ReleaseVersion("99.0.0")!, tag: "v99.0.0", notes: "A sample update for this test.", asset: asset)
    }
    func download(_ release: UpdateRelease) async throws -> URL {
        guard downloadable else { throw UpdateError.noInstaller }
        let file = try UpdateFiles.makeTemporaryDirectory().appendingPathComponent("sample-update.dmg")
        try Data("UI fixture only.".utf8).write(to: file)
        return file
    }
}
@MainActor
private struct FixtureUpdateInstaller: UpdateInstalling {
    func install(_ diskImage: URL, release: UpdateRelease) async throws { throw UpdateError.noInstaller }
}
#endif
