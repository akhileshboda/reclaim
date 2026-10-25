import AppKit
import SwiftUI
import ReclaimCore

/// The largest items in a drive's Trash, each with Show in Finder (where Put Back works) and
/// Erase Immediately.
struct TrashPeekList: View {
    let model: AppModel
    let state: DriveState

    static let visibleCount = 6

    var body: some View {
        let shown = Array(state.trash.largestItems.prefix(Self.visibleCount))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { item in
                TrashPeekRow(item: item, reveal: { model.reveal(item) }, erase: {
                    Task { await model.deleteItems([item], driveID: state.id) }
                })
            }
            let hidden = state.trash.itemCount - shown.count
            if hidden > 0 {
                Text("and \(hidden.formatted()) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .padding(.leading, 26)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Largest items in the Trash on \(state.drive.name)")
    }
}

private struct TrashPeekRow: View {
    let item: TrashItem
    let reveal: () -> Void
    let erase: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let deleted = item.dateDeleted {
                    Text("Deleted \(deleted, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Text(ByteFormat.string(item.bytes))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(action: reveal) {
                    Image(systemName: "magnifyingglass").iconHitTarget()
                }
                .buttonStyle(.borderless)
                .help("Show in Finder, where you can Put Back")
                .accessibilityLabel("Show \(item.name) in Finder")
                Button(action: erase) {
                    Image(systemName: "trash").iconHitTarget()
                }
                .buttonStyle(.borderless)
                .help("Erase Immediately…")
                .accessibilityLabel("Erase \(item.name) immediately")
            }
        }
        .contextMenu {
            Button("Show in Finder", action: reveal)
            Divider()
            Button("Erase Immediately…", action: erase)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12) : .clear))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Show in Finder", reveal)
        .accessibilityAction(named: "Erase Immediately", erase)
    }
}
