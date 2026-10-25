import SwiftUI
import ReclaimCore

struct DriveRow: View {
    let state: DriveState
    let activity: AppModel.Activity?
    let askBeforeEmptying: Bool
    let onEmpty: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            BreakdownBar(breakdown: state.breakdown, driveName: state.drive.name)
            BreakdownLegend(breakdown: state.breakdown)
            trashRow
        }
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(for: state.drive))
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.drive.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(ByteFormat.string(state.breakdown.free)) free of \(ByteFormat.string(state.drive.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var trashRow: some View {
        HStack(spacing: 8) {
            switch (activity, state.trash.access) {
            case (.some, _):
                ProgressView().controlSize(.small)
                Text(activity == .emptying ? "Emptying Trash…" : "Erasing…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            case (nil, .denied):
                Label("Needs Full Disk Access to read this Trash", systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            case (nil, .unavailable):
                Text("No Trash on this drive yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            case (nil, .readable):
                trashSummary
                Spacer(minLength: 0)
                Button(askBeforeEmptying ? "Empty Trash…" : "Empty Trash", action: onEmpty)
                    .controlSize(.small)
                    .disabled(!state.canEmpty)
                    .accessibilityHint("Permanently erases the items in this drive’s Trash")
            }
        }
        .frame(minHeight: 22)
    }

    private var trashSummary: some View {
        HStack(spacing: 6) {
            if state.canEmpty {
                SegmentSwatch(segment: .trash)
                Text("\(ByteFormat.string(state.trash.totalBytes)) in Trash")
                    .foregroundStyle(.primary)
                + Text(" · \(ConfirmationRequest.itemPhrase(state.trash.itemCount))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Trash is empty").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .monospacedDigit()
    }

    static func symbol(for drive: DriveInfo) -> String {
        if drive.isNetwork { return "server.rack" }
        if drive.isBoot || drive.isInternal { return "internaldrive" }
        return "externaldrive"
    }
}
