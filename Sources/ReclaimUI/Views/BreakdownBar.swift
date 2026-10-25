import SwiftUI
import ReclaimCore

/// The four storage segments, using system colours so they adapt to Dark Mode and
/// Increase Contrast automatically.
public enum StorageSegment: CaseIterable, Identifiable, Sendable {
    case used, trash, purgeable, free

    public var id: Self { self }

    public var title: String {
        switch self {
        case .used: "Used"
        case .trash: "In Trash"
        case .purgeable: "Purgeable"
        case .free: "Free"
        }
    }

    public var color: Color {
        switch self {
        case .used: Color(nsColor: .systemBlue)
        case .trash: Color(nsColor: .systemOrange)
        case .purgeable: Color(nsColor: .systemGray)
        case .free: Color(nsColor: .quaternaryLabelColor)
        }
    }

    /// Patterned segments stay distinguishable when Differentiate Without Colour is on.
    var isPatterned: Bool { self == .trash || self == .purgeable }

    func bytes(in breakdown: SpaceBreakdown) -> Int64 {
        switch self {
        case .used: breakdown.used
        case .trash: breakdown.trash
        case .purgeable: breakdown.purgeable
        case .free: breakdown.free
        }
    }
}

/// A capsule split into Used / In Trash / Purgeable / Free.
public struct BreakdownBar: View {
    let breakdown: SpaceBreakdown
    let driveName: String

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(breakdown: SpaceBreakdown, driveName: String) {
        self.breakdown = breakdown
        self.driveName = driveName
    }

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(StorageSegment.allCases) { segment in
                    let width = proxy.size.width * breakdown.fraction(of: segment.bytes(in: breakdown))
                    Rectangle()
                        .fill(segment.color)
                        .overlay {
                            if differentiateWithoutColor && segment.isPatterned {
                                Stripes().stroke(Color.primary.opacity(0.45), lineWidth: 1)
                            }
                        }
                        .frame(width: max(0, width))
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: breakdown)
        .accessibilityElement()
        .accessibilityLabel("Storage on \(driveName)")
        .accessibilityValue(Self.accessibilityValue(for: breakdown))
    }

    static func accessibilityValue(for b: SpaceBreakdown) -> String {
        var parts = ["\(ByteFormat.string(b.used)) used"]
        if b.trash > 0 { parts.append("\(ByteFormat.string(b.trash)) in Trash") }
        if b.purgeable > 0 { parts.append("\(ByteFormat.string(b.purgeable)) purgeable") }
        parts.append("\(ByteFormat.string(b.free)) free of \(ByteFormat.string(b.total))")
        return parts.joined(separator: ", ")
    }
}

private struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 4
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

/// Two-column legend: coloured marker, name, value. Trash has its own row under the legend, and
/// Purgeable only shows when there is some.
struct BreakdownLegend: View {
    let breakdown: SpaceBreakdown

    var body: some View {
        let segments: [StorageSegment] = breakdown.purgeable > 0 ? [.used, .purgeable, .free] : [.used, .free]
        let rows = stride(from: 0, to: segments.count, by: 2).map { Array(segments[$0..<min($0 + 2, segments.count)]) }
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 2) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(rows[index]) { segment in
                        LegendEntry(segment: segment, bytes: segment.bytes(in: breakdown))
                    }
                }
            }
        }
        .font(.caption)
        .accessibilityHidden(true) // The bar already speaks these values.
    }
}

struct SegmentSwatch: View {
    let segment: StorageSegment

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(segment.color)
            .frame(width: 8, height: 8)
    }
}

private struct LegendEntry: View {
    let segment: StorageSegment
    let bytes: Int64

    var body: some View {
        HStack(spacing: 4) {
            SegmentSwatch(segment: segment)
            Text(segment.title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(ByteFormat.string(bytes))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 130)
    }
}
