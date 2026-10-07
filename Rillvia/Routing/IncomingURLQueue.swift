import Foundation

enum IncomingURLDisposition: Equatable, Sendable {
    case consumed
    case retryLater
}

@MainActor
final class IncomingURLQueue {
    typealias Handler = @MainActor (URL) async -> IncomingURLDisposition

    private var pending: [URL] = []
    private var handler: Handler?
    private var isDraining = false

    var pendingCount: Int {
        pending.count
    }

    func enqueue(_ urls: [URL]) {
        pending.append(contentsOf: urls)
    }

    func attach(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func drain() async {
        guard !isDraining, let handler else {
            return
        }
        isDraining = true
        defer { isDraining = false }

        while let url = pending.first {
            switch await handler(url) {
            case .consumed:
                pending.removeFirst()
            case .retryLater:
                return
            }
        }
    }
}
