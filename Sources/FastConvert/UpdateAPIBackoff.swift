import Foundation

/// Persistent REST cooldown has one owner and a finite lifetime. Link-based
/// checks stay available independently of this API quota. Recording the clock
/// at the response prevents a later clock correction from blocking checks for
/// weeks; old records are normalized once when read.
@MainActor
struct UpdateAPIBackoff {
    nonisolated static let maximumWait: TimeInterval = 24 * 60 * 60
    private static let deadlineKey = "com.ixiehao.MP4Flow.updates.apiRetryNotBefore"
    private static let recordedAtKey = "com.ixiehao.MP4Flow.updates.apiRetryRecordedAt"
    let defaults: UserDefaults

    func isActive(at current: Date) -> Bool {
        guard let deadline = defaults.object(forKey: Self.deadlineKey) as? Date else { return false }
        guard deadline.timeIntervalSince1970.isFinite, deadline > current else {
            clear()
            return false
        }
        let recorded = defaults.object(forKey: Self.recordedAtKey) as? Date
        if let recorded, !recorded.timeIntervalSince1970.isFinite || current < recorded {
            clear()
            return false
        }
        let start = recorded ?? current
        let bounded = min(deadline, start.addingTimeInterval(Self.maximumWait))
        guard current < bounded else { clear(); return false }
        if recorded == nil { defaults.set(start, forKey: Self.recordedAtKey) }
        if bounded != deadline { defaults.set(bounded, forKey: Self.deadlineKey) }
        return true
    }

    func record(_ response: HTTPURLResponse, at current: Date) {
        let maximum = current.addingTimeInterval(Self.maximumWait)
        var deadline = current.addingTimeInterval(60)
        if let raw = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let timestamp = TimeInterval(raw), timestamp.isFinite {
            deadline = max(deadline, min(Date(timeIntervalSince1970: timestamp), maximum))
        }
        if let raw = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(raw), seconds.isFinite, seconds >= 0 {
                deadline = max(deadline, current.addingTimeInterval(min(seconds, Self.maximumWait)))
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                if let date = formatter.date(from: raw) { deadline = max(deadline, min(date, maximum)) }
            }
        }
        defaults.set(current, forKey: Self.recordedAtKey)
        defaults.set(deadline, forKey: Self.deadlineKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.deadlineKey)
        defaults.removeObject(forKey: Self.recordedAtKey)
    }
}
