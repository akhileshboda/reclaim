import Foundation

/// Decides when to warn that a drive is nearly full, without nagging: one alert when available
/// space (free + purgeable) drops below the threshold, then quiet until it recovers by a margin
/// or a day passes.
public struct LowSpaceTracker: Sendable {
    public struct Alert: Sendable, Equatable {
        public let driveID: String
        public let driveName: String
        public let availableBytes: Int64
        public let reclaimableBytes: Int64
    }

    public var thresholdPercent: Int
    public var rearmMarginPercent = 2
    public var repeatInterval: TimeInterval = 24 * 60 * 60
    private var alerted: [String: Date] = [:]

    public init(thresholdPercent: Int) {
        self.thresholdPercent = thresholdPercent
    }

    /// Returns the alerts to show now, given each drive's capacity breakdown.
    public mutating func evaluate(_ drives: [(id: String, name: String, breakdown: SpaceBreakdown, isReadOnly: Bool)], now: Date = Date()) -> [Alert] {
        var alerts: [Alert] = []
        for drive in drives where !drive.isReadOnly && drive.breakdown.total > 0 {
            let available = drive.breakdown.free + drive.breakdown.purgeable
            let percent = Double(available) / Double(drive.breakdown.total) * 100
            if percent >= Double(thresholdPercent + rearmMarginPercent) {
                alerted[drive.id] = nil
                continue
            }
            guard percent < Double(thresholdPercent) else { continue }
            if let last = alerted[drive.id], now.timeIntervalSince(last) < repeatInterval { continue }
            alerted[drive.id] = now
            alerts.append(Alert(driveID: drive.id, driveName: drive.name, availableBytes: available, reclaimableBytes: drive.breakdown.trash))
        }
        return alerts
    }

    /// Title-style title without ending punctuation; the body states facts rather than telling
    /// people what to do (the notification offers an Empty Trash… action instead).
    public static func message(for alert: Alert) -> (title: String, body: String) {
        let title = "“\(alert.driveName)” Is Almost Full"
        var body = "Only \(ByteFormat.string(alert.availableBytes)) is available."
        if alert.reclaimableBytes > 0 {
            body += " \(ByteFormat.string(alert.reclaimableBytes)) is in its Trash."
        }
        return (title, body)
    }
}
