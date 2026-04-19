import Foundation

/// Writes a human-readable dump of the current `CalendarService.upcomingCommutes`
/// pass to `~/Library/Logs/Ping/calendar-diagnostic.log`. The file is rewritten
/// from scratch on every run so the newest snapshot is always at the top.
///
/// This is intentionally always-on (rather than gated on DEBUG) so I can ask
/// users to `cat` the file when debugging a "my event isn't showing up" bug
/// without rebuilding. The payload is tiny (a few kilobytes) and contains only
/// data the app already reads locally.
enum CalendarDiagnosticLog {
    nonisolated(unsafe) private static var buffer: [String] = []
    private static let queue = DispatchQueue(label: "app.ping.calendar-diagnostic")

    static func beginSnapshot(window: (Date, Date), totalRecords: Int) {
        queue.sync {
            buffer.removeAll(keepingCapacity: true)
            buffer.append("== Ping calendar snapshot ==")
            buffer.append("Generated: \(Date())")
            buffer.append("Window:    \(window.0) -> \(window.1)")
            buffer.append("Total EventKit records in window: \(totalRecords)")
            buffer.append("")
        }
    }

    static func record(_ record: CalendarEventRecord, disposition: String) {
        queue.sync {
            buffer.append("- \(record.title)")
            buffer.append("    start:       \(record.startDate)")
            buffer.append("    id:          \(record.id)")
            buffer.append("    location:    \(record.location ?? "(nil)")")
            if let coord = record.coordinate {
                buffer.append("    coordinate:  lat=\(coord.latitude) lon=\(coord.longitude)")
            } else {
                buffer.append("    coordinate:  (nil)")
            }
            buffer.append("    result:      \(disposition)")
            buffer.append("")
        }
    }

    static func write(_ line: String) {
        queue.sync { buffer.append(line) }
    }

    static func finish(commuteCount: Int) {
        queue.sync {
            buffer.append("== Finished: produced \(commuteCount) CommuteEvent(s) ==")
            flushLocked()
        }
    }

    private static func flushLocked() {
        let fm = FileManager.default
        guard
            let logsDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("Ping", isDirectory: true)
        else { return }

        try? fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let url = logsDir.appendingPathComponent("calendar-diagnostic.log")
        let text = buffer.joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
