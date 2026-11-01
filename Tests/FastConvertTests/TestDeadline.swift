import Foundation

/// Match the process watchdog's monotonic, sleep-excluding clock. A laptop
/// suspension must not consume a fixture's active-processing time budget.
struct TestDeadline {
    private let end: TimeInterval
    init(seconds: TimeInterval) { end = ProcessInfo.processInfo.systemUptime + seconds }
    var hasTimeRemaining: Bool { ProcessInfo.processInfo.systemUptime < end }
}
