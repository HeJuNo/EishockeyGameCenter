import Foundation

enum LoadState: Equatable {
    case loading, loaded, failed

    /// The state a load error leads to; nil for errors that are no real failure (a navigation we or the user cancelled).
    static func failure(for error: Error) -> LoadState? {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return nil }
        if e.domain == "WebKitErrorDomain" && e.code == 102 { return nil }  // frame load interrupted by policy change
        return .failed
    }
}
