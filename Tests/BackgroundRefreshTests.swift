import Foundation
import Testing
@testable import EishockeyGameCenter

@MainActor @Suite struct BackgroundRefreshTests {
    @Test func nextDateIsFifteenMinutesLater() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(BackgroundRefresh.nextDate(after: now) == now.addingTimeInterval(15 * 60))
    }

    @Test func taskIdentifierIsDerivedFromTheBundleIdentifier() {
        #expect(BackgroundRefresh.taskIdentifier == (Bundle.main.bundleIdentifier ?? "") + ".refresh")
    }
}
