import SwiftUI
import ReclaimCore

/// Callbacks the AppKit shell provides to the panel.
public struct PanelActions {
    public var openSettings: () -> Void
    public var openFullDiskAccessSettings: () -> Void
    public var checkForUpdates: () -> Void
    public var showAbout: () -> Void
    public var quit: () -> Void

    public init(
        openSettings: @escaping () -> Void = {},
        openFullDiskAccessSettings: @escaping () -> Void = {},
        checkForUpdates: @escaping () -> Void = {},
        showAbout: @escaping () -> Void = {},
        quit: @escaping () -> Void = {}
    ) {
        self.openSettings = openSettings
        self.openFullDiskAccessSettings = openFullDiskAccessSettings
        self.checkForUpdates = checkForUpdates
        self.showAbout = showAbout
        self.quit = quit
    }
}

/// The popover shown from the menu bar.
public struct PanelView: View {
    @Bindable var model: AppModel
    let actions: PanelActions
    /// Drives whose Trash peek starts expanded (used by screenshots).
    let expandedTrashPeeks: Set<String>

    public static let width: CGFloat = 340

    public init(model: AppModel, actions: PanelActions = PanelActions(), expandedTrashPeeks: Set<String> = []) {
        self.model = model
        self.actions = actions
        self.expandedTrashPeeks = expandedTrashPeeks
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if let update = model.availableUpdate {
                UpdateBanner(release: update)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            if model.needsFullDiskAccess {
                FullDiskAccessBanner(openSettings: actions.openFullDiskAccessSettings)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()
            driveList
            Divider()

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: Self.width)
        .task(id: model.notice?.id) {
            guard model.notice != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            model.notice = nil
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Reclaim").font(.headline)
                    if model.mode == .sandbox {
                        Text("Sandbox")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color(nsColor: .systemPurple).opacity(0.2)))
                            .foregroundStyle(Color(nsColor: .systemPurple))
                            .accessibilityLabel("Sandbox mode: test disks only")
                    }
                }
                Text(summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            moreMenu
        }
    }

    private var summaryText: String {
        guard model.hasLoaded else { return "Measuring drives…" }
        let reclaimable = model.totalReclaimable
        guard reclaimable > 0 else { return "Nothing to reclaim. All Trash is empty." }
        let count = model.emptiableDrives.count
        return "\(ByteFormat.string(reclaimable)) can be reclaimed\(count > 1 ? " across \(count) drives" : "")"
    }

    private var moreMenu: some View {
        Menu {
            Button("Settings…", action: actions.openSettings)
                .keyboardShortcut(",")
            Button("Check for Updates…", action: actions.checkForUpdates)
            Button("About Reclaim", action: actions.showAbout)
            Divider()
            Button("Quit Reclaim", action: actions.quit)
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
        .help("Settings and more")
    }

    @ViewBuilder private var driveList: some View {
        if !model.hasLoaded {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else if model.drives.isEmpty {
            ContentUnavailableView(
                "No Drives",
                systemImage: "externaldrive.badge.questionmark",
                description: Text(model.mode == .sandbox ? "Run Scripts/sandbox.sh up to attach the test disks." : "Connect a drive to see it here.")
            )
            .frame(minHeight: 160)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.drives.enumerated()), id: \.element.id) { index, state in
                        if index > 0 { Divider() }
                        DriveRow(model: model, state: state, showsLargestItems: expandedTrashPeeks.contains(state.id))
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 520)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var footer: some View {
        if let notice = model.notice {
            NoticeView(notice: notice)
                .transition(.opacity)
        } else {
            Button {
                Task { await model.emptyAllTrash() }
            } label: {
                Text(model.settings.askBeforeEmptying ? "Empty All Trash…" : "Empty All Trash")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(model.emptiableDrives.isEmpty || !model.activity.isEmpty)
            .help("Permanently erase the Trash on every drive")
        }
    }
}

struct UpdateBanner: View {
    let release: Release

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Reclaim \(release.version?.description ?? release.tagName) is available.")
                .font(.callout)
            Spacer(minLength: 4)
            Link("Download", destination: release.htmlURL)
                .font(.callout)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }
}

struct NoticeView: View {
    let notice: Notice

    var body: some View {
        Label {
            Text(notice.text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: notice.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(notice.kind == .success ? Color(nsColor: .systemGreen) : Color(nsColor: .systemYellow))
        }
        .font(.callout)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
