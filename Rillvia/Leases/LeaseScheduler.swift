import Foundation

@MainActor
protocol BrowserLeaseScheduling: AnyObject {
    func schedule(at deadline: Date, action: @escaping () -> Void)
    func cancel()
}

@MainActor
final class LeaseScheduler: BrowserLeaseScheduling {
    private let now: () -> Date
    private var task: Task<Void, Never>?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func schedule(at deadline: Date, action: @escaping () -> Void) {
        cancel()
        let delay = max(0, deadline.timeIntervalSince(now()))
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.task = nil
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
