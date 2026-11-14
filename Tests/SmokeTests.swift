import Testing
@testable import EishockeyGameCenter

@MainActor @Suite struct SmokeTests {
    @Test func appModuleLoads() {
        #expect(EishockeyGameCenterApp.self == EishockeyGameCenterApp.self)
    }
}
