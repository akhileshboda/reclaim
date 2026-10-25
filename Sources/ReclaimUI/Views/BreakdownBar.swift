import SwiftUI
import ReclaimCore

/// The four storage segments, using system colours so they adapt to Dark Mode and
/// Increase Contrast automatically. Bar order puts In Trash next to Free: it's the part of the
/// drive that becomes free when the Trash is emptied.
public enum StorageSegment: CaseIterable, Identifiable, Sendable {
    case used, purgeable, trash, free

    public var id: Self { self }

    public var title: String {
        switch self {
        case .used: "Used"
        case .purgeable: "Purgeable"
        case .trash: "In Trash"
        case .free: "Free"
        }
    }

    public var color: Color {
        switch self {
        case .used: Color(nsColor: .systemBlue)
        case .purgeable: Color(nsColor: .systemGray)
        case .trash: Color(nsColor: .systemOrange)
        case .free: Color(nsColor: .quaternarySystemFill)
        }
    }

    /// A distinct texture per segment, shown when Differentiate Without Colour is on.
    var pattern: SegmentPattern? {
        switch self {
        case .used: nil
        case .purgeable: .dots
        case .trash: .stripes
        case .free: nil
        }
    }

    func bytes(in breakdown: SpaceBreakdown) -> Int64 {
        switch self {
        case .used: breakdown.used
        case .purgeable: breakdown.purgeable
        case .trash: breakdown.trash
        case .free: breakdown.free
        }
    }
}

enum SegmentPattern {
    case stripes, dots
}

/// A capsule split into Used / Purgeable / In Trash / Free.
public struct BreakdownBar: View {
    let breakdown: SpaceBreakdown
    let driveName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(breakdown: SpaceBreakdown, driveName: String) {
        self.breakdown = breakdown
        self.driveName = driveName
    }

    public var body: some View {
        GeometryReader { proxy in
            let visible = StorageSegment.allCases.filter { $0.bytes(in: breakdown) > 0 }
            let gaps = CGFloat(max(0, visible.count - 1))
            HStack(spacing: 1) {
                ForEach(visible) { segment in
                    SegmentFill(segment: segment)
                        .frame(width: max(0, (proxy.size.width - gaps) * breakdown.fraction(of: segment.bytes(in: breakdown))))
                }
            }
        }
        .frame(height: 8)
        .background(StorageSegment.free.color)
        .clipShape(Capsule())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: breakdown)
        .accessibilityElement()
        .accessibilityLabel("Storage on \(driveName)")
        .accessibilityValue(Self.accessibilityValue(for: breakdown))
    }

    static func accessibilityValue(for b: SpaceBreakdown) -> String {
        var parts = ["\(ByteFormat.string(b.used)) used"]
        if b.purgeable > 0 { parts.append("\(ByteFormat.string(b.purgeable)) purgeable") }
        if b.trash > 0 { parts.append("\(ByteFormat.string(b.trash)) in Trash") }
        parts.append("\(ByteFormat.string(b.free)) free of \(ByteFormat.string(b.total))")
        return parts.joined(separator: ", ")
    }
}

/// A segment's colour plus, under Differentiate Without Colour, its pattern.
struct SegmentFill: View {
    let segment: StorageSegment
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Rectangle()
            .fill(segment.color)
            .overlay {
                if differentiateWithoutColor, let pattern = segment.pattern {
                    PatternShape(pattern: pattern)
                        .fill(Color.primary.opacity(0.55))
                }
            }
    }
}

private struct PatternShape: Shape {
    let pattern: SegmentPattern

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch pattern {
        case .stripes:
            var x = rect.minX - rect.height
            while x < rect.maxX {
                path.move(to: CGPoint(x: x, y: rect.maxY))
                path.addLine(to: CGPoint(x: x + 1.2, y: rect.maxY))
                path.addLine(to: CGPoint(x: x + rect.height + 1.2, y: rect.minY))
                path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                path.closeSubpath()
                x += 4
            }
        case .dots:
            var y = rect.minY + 1.5
            var row = 0
            while y < rect.maxY {
                var x = rect.minX + (row.isMultiple(of: 2) ? 1.5 : 3.5)
                while x < rect.maxX {
                    path.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                    x += 4
                }
                y += 2.5
                row += 1
            }
        }
        return path
    }
}

struct SegmentSwatch: View {
    let segment: StorageSegment

    var body: some View {
        SegmentFill(segment: segment)
            .frame(width: 10, height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 2.5))
            .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(Color(nsColor: .separatorColor), lineWidth: segment == .free ? 1 : 0))
            .accessibilityHidden(true)
    }
}

/// "■ Used 406.8 GB   ■ Purgeable 22 GB   ■ Free 61 GB": each value right next to its label,
/// entries in bar order, wrapping when space runs out. In Trash has its own row below.
struct BreakdownLegend: View {
    let breakdown: SpaceBreakdown

    var body: some View {
        let segments = StorageSegment.allCases.filter { $0 != .trash && ($0 != .purgeable || breakdown.purgeable > 0) }
        FlowLayout(horizontalSpacing: 16, verticalSpacing: 3) {
            ForEach(segments) { segment in
                HStack(spacing: 5) {
                    SegmentSwatch(segment: segment)
                    Text(segment.title).foregroundStyle(.secondary)
                    Text(ByteFormat.string(segment.bytes(in: breakdown)))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
        }
        .font(.caption)
        .accessibilityHidden(true) // The bar already speaks these values.
    }
}

/// Lays children out left to right, wrapping to a new line when the next one doesn't fit.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + verticalSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + horizontalSpacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + horizontalSpacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
