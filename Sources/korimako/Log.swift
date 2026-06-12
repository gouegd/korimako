import Foundation

/// Lightweight debug logging, enabled only when `KORIMAKO_DEBUG` is set.
/// Emits via NSLog so it's visible both on stderr (direct launch) and in the
/// unified log (`log show --predicate 'eventMessage CONTAINS "korimako"'`).
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["KORIMAKO_DEBUG"] != nil

    static func debug(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        NSLog("korimako: \(message())")
    }
}
