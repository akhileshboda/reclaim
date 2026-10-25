import Foundation

/// What the menu bar item shows next to its icon.
public enum BadgeMode: String, CaseIterable, Sendable, Identifiable {
    /// Show the reclaimable size once it passes the threshold.
    case automatic
    case always
    case iconOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "When there's 1 GB or more to reclaim"
        case .always: "Always"
        case .iconOnly: "Never"
        }
    }

    public static let automaticThreshold: Int64 = 1_000_000_000

    /// The badge text, or nil to show the icon alone.
    public func text(reclaimable: Int64) -> String? {
        switch self {
        case .iconOnly: nil
        case .always: ByteFormat.badge(reclaimable)
        case .automatic: reclaimable >= Self.automaticThreshold ? ByteFormat.badge(reclaimable) : nil
        }
    }
}
