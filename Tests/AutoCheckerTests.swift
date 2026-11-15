import Foundation
import Testing
@testable import EishockeyGameCenter

@MainActor @Suite struct AutoCheckerTests {
    private final class Counter { var runs = 0 }

    @Test func runsAtOnceThenEveryInterval() async throws {
        let counter = Counter()
        let checker = AutoChecker(interval: .milliseconds(40)) { counter.runs += 1 }
        checker.start()
        try await Task.sleep(for: .milliseconds(300))
        checker.stop()
        #expect(counter.runs >= 4)                // the first run at once, then repeatedly
    }

    @Test func stopHaltsAndStartTwiceIsOneLoop() async throws {
        let counter = Counter()
        let checker = AutoChecker(interval: .milliseconds(40)) { counter.runs += 1 }
        checker.start(); checker.start()          // a second start must not start a second loop
        try await Task.sleep(for: .milliseconds(200))
        checker.stop()
        let atStop = counter.runs
        try await Task.sleep(for: .milliseconds(200))
        #expect(counter.runs == atStop)           // nothing after stop
        #expect(atStop < 12)                      // roughly one run per 40 ms, not two
    }
}
