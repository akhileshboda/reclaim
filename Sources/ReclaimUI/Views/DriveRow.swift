import SwiftUI
import ReclaimCore

/// One drive as a card: name and capacity, the storage bar, and what's in its Trash.
struct DriveRow: View {
    let model: AppModel
    let state: DriveState
    /// Position in the list, for the staggered first appearance.
    let index: Int

    @State private var showsLargestItems: Bool
    @State private var isHovered = false
    /// The bar grows in the first time this drive is shown, not every time the panel opens.
    @State private var revealed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.entranceAnimations) private var entranceAnimations

    init(model: AppModel, state: DriveState, index: Int = 0, showsLargestItems: Bool = false) {
        self.model = model
        self.state = state
        self.index = index
        _showsLargestItems = State(initialValue: showsLargestItems)
        _revealed = State(initialValue: false)
    }

    private var activity: AppModel.Activity? { model.activity[state.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            BreakdownBar(breakdown: state.breakdown, driveName: state.drive.name, revealed: revealed || !entranceAnimations)
            BreakdownLegend(breakdown: state.breakdown)
            trashRow
            if showsLargestItems, state.canEmpty, activity == nil {
                TrashPeekList(model: model, state: state)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(highlighted: isHovered)
        .onHover { hovering in withAnimation(Motion.hover) { isHovered = hovering } }
        .onAppear {
            guard !revealed else { return }
            if reduceMotion || !entranceAnimations {
                revealed = true
            } else {
                withAnimation(Motion.easeOut(0.5).delay(0.05 + Double(index) * 0.06)) { revealed = true }
            }
        }
        .onChange(of: state.canEmpty) { _, canEmpty in
            if !canEmpty { showsLargestItems = false }
        }
        .onChange(of: model.peekRequest) { _, request in
            if request?.driveID == state.id, state.canEmpty { togglePeek(true) }
        }
    }

    private func togglePeek(_ show: Bool? = nil) {
        withAnimation(reduceMotion ? nil : Motion.easeOut(0.25)) { showsLargestItems = show ?? !showsLargestItems }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(for: state.drive))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(state.canEmpty ? Brand.emberText : Color.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(state.canEmpty ? Color(hex: 0xFF8F24).opacity(0.16) : Color(nsColor: .quaternaryLabelColor).opacity(0.35)))
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
                    Image(systemName: "eject.fill").iconHitTarget()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
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
                    togglePeek()
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle").iconHitTarget()
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
                BoomerangSpinner(size: 14).accessibilityHidden(true)
                Text(Self.activityText(activity))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if activity == .scanningJunk {
                    Button("Stop") { model.cancelJunkScan(driveID: state.id) }
                        .controlSize(.small)
                        .help("Stop looking for hidden files")
                }
            } else if state.isMeasuring, !state.canEmpty {
                BoomerangSpinner(size: 14).accessibilityHidden(true)
                Text("Measuring the Trash…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                switch state.trash.access {
                case .denied:
                    Label(state.drive.isBoot ? "Needs Full Disk Access" : "Not allowed to read this drive",
                          systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    // Every denied row gets a way forward, not just the banner (which can be dismissed).
                    Button(state.drive.isBoot ? "Grant Access…" : "Allow…") { model.openPrivacySettings(for: state) }
                        .controlSize(.small)
                        .help(state.drive.isBoot
                              ? "Open Full Disk Access in Privacy & Security, then turn on Reclaim"
                              : "Turn on Removable Volumes for Reclaim in Privacy & Security › Files & Folders")
                        .accessibilityHint("Opens Privacy & Security settings")
                case .unavailable:
                    Label("No Trash folder on this drive", systemImage: "trash.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                case .readable:
                    trashSummary
                    Spacer(minLength: 0)
                    if state.canEmpty {
                        Button(model.settings.askBeforeEmptying ? "Empty…" : "Empty") {
                            Task { await model.emptyTrash(driveID: state.id) }
                        }
                        .help("Permanently erase the Trash on “\(state.drive.name)”")
                        .accessibilityLabel("Empty Trash on \(state.drive.name)")
                        .accessibilityHint("Permanently erases the items in this drive’s Trash")
                    } else if state.drive.isReadOnly, state.trash.totalBytes > 0 {
                        Text("Read-only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("macOS mounted this drive read-only, so its Trash can’t be emptied")
                    }
                }
            }
        }
        .frame(minHeight: 26)
    }

    private var trashSummary: some View {
        Group {
            if state.trash.itemCount > 0 || state.trash.totalBytes > 0 {
                Button {
                    togglePeek()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(showsLargestItems ? 90 : 0))
                        Text("\(ByteFormat.string(state.trash.totalBytes)) in Trash")
                            .fontWeight(.semibold)
                        Text("· \(ConfirmationRequest.itemPhrase(state.trash.itemCount))")
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .foregroundStyle(Brand.emberText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: 0xFF8F24).opacity(0.15)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!state.canEmpty)
                .help(showsLargestItems ? "Hide the largest items" : "Show the largest items in this Trash")
                .accessibilityLabel("Largest items in Trash, \(ByteFormat.string(state.trash.totalBytes)), \(ConfirmationRequest.itemPhrase(state.trash.itemCount))")
                .accessibilityValue(showsLargestItems ? "Expanded" : "Collapsed")
            } else {
                Label("Trash is empty", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
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
