import CryptoKit
import Foundation

protocol UpdateProviding {
    func latestRelease() async throws -> UpdateRelease?
    func download(_ release: UpdateRelease) async throws -> URL
}

struct GitHubUpdateClient: UpdateProviding {
    private let session: URLSession
    private let cli: URL?

    init(session: URLSession? = nil, cli: URL? = Self.installedCLI) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        // Installers are tens of megabytes; slow connections need longer than three minutes.
        configuration.timeoutIntervalForResource = 600
        self.session = session ?? URLSession(configuration: configuration)
        self.cli = cli
    }

    static var installedCLI: URL? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func latestRelease() async throws -> UpdateRelease? {
        var request = URLRequest(url: UpdateSource.apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.downloadFailed }
        if http.statusCode == 200 { return try GitHubReleaseDocument.latest(in: data) }
        guard [401, 403, 404].contains(http.statusCode) else { throw UpdateError.downloadFailed }
        guard let cli else { throw UpdateError.accessRequired }
        let directory = try UpdateFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("releases.json")
        do {
            try await UpdateTool.run(cli, ["api", "repos/\(UpdateSource.repository)/releases?per_page=100"], output: output)
        } catch { throw UpdateError.accessRequired }
        return try GitHubReleaseDocument.latest(in: Data(contentsOf: output))
    }

    func download(_ release: UpdateRelease) async throws -> URL {
        guard let asset = release.asset else { throw UpdateError.noInstaller }
        let directory = try UpdateFiles.makeTemporaryDirectory()
        let destination = directory.appendingPathComponent(asset.name)
        do {
            let (download, response) = try await session.download(from: asset.downloadURL)
            guard let http = response as? HTTPURLResponse else { throw UpdateError.downloadFailed }
            if http.statusCode == 200 {
                try FileManager.default.moveItem(at: download, to: destination)
            } else if [401, 403, 404].contains(http.statusCode) {
                try? FileManager.default.removeItem(at: download)
                guard let cli else { throw UpdateError.accessRequired }
                do {
                    try await UpdateTool.run(cli, ["api", "repos/\(UpdateSource.repository)/releases/assets/\(asset.id)",
                        "--header", "Accept: application/octet-stream"], output: destination, timeout: 600)
                } catch UpdateError.timeout {
                    throw UpdateError.timeout
                } catch {
                    throw UpdateError.downloadFailed
                }
            } else {
                try? FileManager.default.removeItem(at: download)
                throw UpdateError.downloadFailed
            }
            try await Task.detached { try UpdateFiles.verify(destination, asset: asset) }.value
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

enum UpdateFiles {
    static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Rillvia-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }

    static func verify(_ file: URL, asset: UpdateAsset) throws {
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        guard size?.int64Value == asset.size else { throw UpdateError.wrongSize }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == asset.sha256 else { throw UpdateError.checksumMismatch }
    }
}

enum UpdateTool {
    /// Uses argument arrays and the CLI's existing credential store. Tokens never enter app preferences or logs.
    static func run(_ executable: URL, _ arguments: [String], output: URL? = nil, timeout: TimeInterval = 60) async throws {
        try await Task.detached { try runSynchronously(executable, arguments, output: output, timeout: timeout) }.value
    }

    static func runSynchronously(_ executable: URL, _ arguments: [String], output: URL? = nil, timeout: TimeInterval = 60) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GH_PROMPT_DISABLED"] = "1"
        process.environment = environment
        process.standardError = FileHandle.nullDevice
        var handle: FileHandle?
        if let output {
            guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw UpdateError.downloadFailed }
            handle = try FileHandle(forWritingTo: output)
        }
        defer { try? handle?.close() }
        process.standardOutput = handle ?? FileHandle.nullDevice
        try process.run()
        let started = Date()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        process.waitUntilExit()
        deadline.cancel()
        guard process.terminationStatus == 0 else {
            throw Date().timeIntervalSince(started) >= timeout ? UpdateError.timeout : UpdateError.toolFailed
        }
    }
}
