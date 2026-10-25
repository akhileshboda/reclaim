import Foundation

public enum ByteFormat {
    /// Formats like Finder does (decimal units, "4.2 GB", "0 bytes").
    public static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    /// Compact form for the menu bar badge: one decimal below 10 ("4.2 GB"), none above ("37 GB").
    public static func badge(_ bytes: Int64) -> String {
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(max(0, bytes)) / 1000
        var unit = 0
        while value >= 999.5, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let digits = value < 9.95 ? 1 : 0
        return "\(value.formatted(.number.precision(.fractionLength(digits)))) \(units[unit])"
    }
}
