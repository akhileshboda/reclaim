import SwiftUI
import ReclaimCore

struct DriveRow: View {
    let model: AppModel
    let state: DriveState

    @State private var showsLargestItems: Bool

    init(model: AppModel, state: DriveState, showsLargestItems: Bool = false) {
        self.model = model
        self.state = state
        _showsLargestItems = State(initialValue: showsLargestItems)
    }

    private var activity: AppModel.Activity? { model.activity[state.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            BreakdownBar(breakdown: state.breakdown, driveName: state.drive.name)
            BreakdownLegend(breakdown: state.breakdown)
            trashRow
            if showsLargestItems, state.canEmpty, activity == nil {
                TrashPeekList(model: model, state: state)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 10)
        .onChange(of: state.canEmpty) { _, canEmpty in
            if !canEmpty { showsLargestItems = false }
        }
    }

    // MARK: Header

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
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if model.canEject(state) {
                Button {
                    Task { await model.eject(driveID: state.id) }
                } label: {
                    Image(systemName: "eject.fill")
                }
                .buttonStyle(.borderless)
                .disabled(activity != nil)
                .help("Eject “\(state.drive.name)”")
                .accessibilityLabel("Eject \(state.drive.name)")
            }
            driveMenu
        }
    }

    private var driveMenu: some View {
        Menu {
            Button("Show in Finder") { model.revealDrive(driveID: state.id) }
            if model.canCleanJunk(state) {
                Button("Remove Hidden macOS Files…") { Task { await model.cleanJunk(driveID: state.id) } }
            }
            if state.canEmpty {
                Divider()
                Button(showsLargestItems ? "Hide Largest Items in Trash" : "Show Largest Items in Trash") {
                    withAnimation { showsLargestItems.toggle() }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(activity != nil)
        .help("More actions for “\(state.drive.name)”")
        .accessibilityLabel("More actions for \(state.drive.name)")
    }

    // MARK: Trash row

    @ViewBuilder private var trashRow: some View {
        HStack(spacing: 8) {
            if let activity {
                ProgressView().controlSize(.small)
                Text(Self.activityText(activity))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                switch state.trash.access {
                case .denied:
                    Label("Needs Full Disk Access to read this Trash", systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                case .unavailable:
                    Text("No Trash on this drive yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                case .readable:
                    trashSummary
                    Spacer(minLength: 0)
                    Button(model.settings.askBeforeEmptying ? "Empty Trash…" : "Empty Trash") {
                        Task { await model.emptyTrash(driveID: state.id) }
                    }
                    .controlSize(.small)
                    .disabled(!state.canEmpty)
                    .accessibilityHint("Permanently erases the items in this drive’s Trash")
                }
            }
        }
        .frame(minHeight: 22)
    }

    private var trashSummary: some View {
        HStack(spacing: 6) {
            if state.canEmpty {
                SegmentSwatch(segment: .trash)
                Button {
                    withAnimation { showsLargestItems.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(ByteFormat.string(state.trash.totalBytes)) in Trash")
                            .foregroundStyle(.primary)
                        + Text(" · \(ConfirmationRequest.itemPhrase(state.trash.itemCount))")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showsLargestItems ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)
                .help(showsLargestItems ? "Hide the largest items" : "Show the largest items in this Trash")
                .accessibilityHint(showsLargestItems ? "Hides the largest items" : "Shows the largest items in this Trash")
            } else {
                Text("Trash is empty").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .monospacedDigit()
    }

    static func activityText(_ activity: AppModel.Activity) -> String {
        switch activity {
        case .emptying: "Emptying Trash…"
        case .deleting: "Erasing…"
        case .scanningJunk: "Looking for hidden macOS files…"
        case .cleaningJunk: "Removing hidden files…"
        case .ejecting: "Ejecting…"
        }
    }

    static func symbol(for drive: DriveInfo) -> String {
        if drive.isNetwork { return "server.rack" }
        if drive.isBoot || drive.isInternal { return "internaldrive" }
        return "externaldrive"
    }
}
