import SwiftUI
import ReclaimCore

/// Callbacks the AppKit shell provides to the panel.
public struct PanelActions {
    public var openSettings: () -> Void
    public var openFullDiskAccessSettings: () -> Void
    public var restart: () -> Void
    public var checkForUpdates: () -> Void
    public var reportBug: () -> Void
    public var showAbout: () -> Void
    public var quit: () -> Void

    public init(
        openSettings: @escaping () -> Void = {},
        openFullDiskAccessSettings: @escaping () -> Void = {},
        restart: @escaping () -> Void = {},
        checkForUpdates: @escaping () -> Void = {},
        reportBug: @escaping () -> Void = {},
        showAbout: @escaping () -> Void = {},
        quit: @escaping () -> Void = {}
    ) {
        self.openSettings = openSettings
        self.openFullDiskAccessSettings = openFullDiskAccessSettings
        self.restart = restart
        self.checkForUpdates = checkForUpdates
        self.reportBug = reportBug
        self.showAbout = showAbout
        self.quit = quit
    }
}

/// The popover shown from the menu bar.
public struct PanelView: View {
    @Bindable var model: AppModel
    let actions: PanelActions
    let layout: PanelLayout
    /// Drives whose Trash peek starts expanded (used by screenshots).
    let expandedTrashPeeks: Set<String>

    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    public static let width: CGFloat = 340

    public init(model: AppModel, actions: PanelActions = PanelActions(), layout: PanelLayout = PanelLayout(), expandedTrashPeeks: Set<String> = []) {
        self.model = model
        self.actions = actions
        self.layout = layout
        self.expandedTrashPeeks = expandedTrashPeeks
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }

            Divider()
            scrollingContent
            Divider()

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { footerHeight = $0 }
        }
        .frame(width: Self.width)
    }

    /// Banners and drives scroll together between the pinned header and footer, so the panel
    /// fits the screen it opens on however many banners, drives and open Trash peeks there are.
    @ViewBuilder private var scrollingContent: some View {
        let limit = PanelLayout.scrollHeightLimit(available: layout.availableHeight, chrome: headerHeight + footerHeight + 2)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                banners
                driveList
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: limit ?? .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var banners: some View {
        let showsUpdate = model.availableUpdate != nil
        let showsAccess = model.needsFullDiskAccess && !model.settings.fullDiskAccessBannerDismissed
        if showsUpdate || showsAccess {
            VStack(spacing: 8) {
                if let update = model.availableUpdate {
                    UpdateBanner(release: update)
                }
                if showsAccess {
                    FullDiskAccessBanner(
                        awaitingToggle: model.awaitingFullDiskAccess,
                        openSettings: actions.openFullDiskAccessSettings,
                        restart: actions.restart,
                        notNow: { withAnimation { model.settings.fullDiskAccessBannerDismissed = true } }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            BrandBadge(size: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Reclaim")
                        .font(.system(.title3, design: .rounded).weight(.bold))
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
                summary
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            moreMenu
        }
    }

    /// "190.6 GB to reclaim across 2 drives", with the amount in Ember: it's the number
    /// the whole app is about.
    private var summary: Text {
        guard model.hasLoaded else { return Text("Measuring drives…") }
        guard !model.drives.isEmpty else { return Text("No drives connected.") }
        let reclaimable = model.totalReclaimable
        guard reclaimable > 0 else { return Text("Nothing to reclaim. All Trash is empty.") }
        let count = model.emptiableDrives.count
        return Text(ByteFormat.string(reclaimable))
            .fontWeight(.semibold)
            .foregroundStyle(Brand.emberText)
            + Text(" to reclaim\(count > 1 ? " across \(count) drives" : "")")
    }

    private var moreMenu: some View {
        Menu {
            Button("About Reclaim", action: actions.showAbout)
            Divider()
            Button("Settings…", action: actions.openSettings)
                .keyboardShortcut(",")
            Button("Check for Updates…", action: actions.checkForUpdates)
            Button("Report a Bug…", action: actions.reportBug)
            Divider()
            Button("Quit Reclaim", action: actions.quit)
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .iconHitTarget()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
        .help("Settings and more")
    }

    @ViewBuilder private var driveList: some View {
        if !model.hasLoaded {
            BoomerangSpinner(size: 22)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else if model.drives.isEmpty {
            ContentUnavailableView(
                "No Drives",
                systemImage: "externaldrive.badge.questionmark",
                description: Text(model.mode == .sandbox ? "Run Scripts/sandbox.sh up to attach the test disks." : "Connect a drive to see it here.")
            )
            .frame(minHeight: 160)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.drives.enumerated()), id: \.element.id) { index, state in
                    if index > 0 { Divider() }
                    DriveRow(model: model, state: state, showsLargestItems: expandedTrashPeeks.contains(state.id))
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: 10) {
            if let notice = model.notice {
                NoticeView(notice: notice, dismiss: { withAnimation { model.notice = nil } })
                    .transition(.opacity)
            }
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

/// The result of the last action. Stays until dismissed (or the panel closes), so nobody has to
/// read it against a timer.
struct NoticeView: View {
    let notice: Notice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon.accessibilityHidden(true)
            Text(notice.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).iconHitTarget()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Dismiss")
            .accessibilityLabel("Dismiss message")
        }
        .font(.callout)
        .padding(.leading, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var icon: some View {
        if notice.reclaimedSpace {
            BoomerangShape()
                .fill(Brand.ember)
                .frame(width: 15, height: 15)
        } else {
            Image(systemName: notice.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(notice.kind == .success ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
        }
    }
}
