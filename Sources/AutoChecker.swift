import Foundation

/// Runs a check at once and then every `interval`, for as long as it is started (the app uses it while it is open).
@MainActor
final class AutoChecker {
    private let interval: Duration
    private let run: @MainActor () async -> Void
    private var task: Task<Void, Never>?

    init(interval: Duration, run: @escaping @MainActor () async -> Void) {
        self.interval = interval
        self.run = run
    }

    func start() {
        guard task == nil else { return }   // one loop only
        task = Task { [interval, run] in
            while !Task.isCancelled {
                await run()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
