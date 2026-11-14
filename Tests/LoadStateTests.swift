import Foundation
import Testing
@testable import EishockeyGameCenter

@MainActor @Suite struct LoadStateTests {
    @Test func cancelledNavigationIsNotAFailure() {
        #expect(LoadState.failure(for: URLError(.cancelled)) == nil)
        #expect(LoadState.failure(for: NSError(domain: "WebKitErrorDomain", code: 102)) == nil)  // frame load interrupted by policy change
    }

    @Test func realNetworkErrorsFail() {
        #expect(LoadState.failure(for: URLError(.notConnectedToInternet)) == .failed)
        #expect(LoadState.failure(for: URLError(.timedOut)) == .failed)
        #expect(LoadState.failure(for: URLError(.cannotFindHost)) == .failed)
    }
}
