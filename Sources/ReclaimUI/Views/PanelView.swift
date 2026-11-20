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
    /// Where the hero ring and the footer sit, for the boomerang's flight between them.
    @State private var ringCenter: CGPoint = .zero
    @State private var footerTop: CGPoint = .zero
    /// Bumps each time space comes back, which plays the celebration.
    @State private var celebrations = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public static let width: CGFloat = 360
    static let space = "panel"

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
                .padding(.top, 12)
                .padding(.bottom, 14)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }

            Divider()
            scrollingContent
            Divider()

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { footerHeight = $0 }
                .onGeometryChange(for: CGPoint.self, of: { proxy in
                    let frame = proxy.frame(in: .named(Self.space))
                    return CGPoint(x: frame.midX, y: frame.minY + 20)
                }) { footerTop = $0 }
        }
        .frame(width: Self.width)
        .coordinateSpace(.named(Self.space))
        .overlay {
            BoomerangFlight(trigger: celebrations, start: footerTop, end: ringCenter)
        }
        .onChange(of: model.notice) { _, notice in
            if notice?.reclaimedSpace == true { celebrations += 1 }
        }
    }

    /// Banners and drives scroll together between the pinned header and footer, so the panel
    /// fits the screen it opens on however many banners, drives and open Trash peeks there are.
    @ViewBuilder private var scrollingContent: some View {
        let limit = PanelLayout.scrollHeightLimit(available: layout.availableHeight, chrome: headerHeight + footerHeight + 8)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                banners
                driveList
            }
            .padding(12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: limit ?? .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var banners: some View {
        if let update = model.availableUpdate {
            UpdateBanner(release: update)
        }
        if model.needsFullDiskAccess, !model.settings.fullDiskAccessBannerDismissed {
            FullDiskAccessBanner(
                awaitingToggle: model.awaitingFullDiskAccess,
                openSettings: actions.openFullDiskAccessSettings,
                restart: actions.restart,
                notNow: { withAnimation { model.settings.fullDiskAccessBannerDismissed = true } }
            )
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                BrandBadge(size: 22)
                Text("Reclaim")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                if model.mode == .sandbox {
                    Text("Sandbox")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color(nsColor: .systemPurple).opacity(0.2)))
                        .foregroundStyle(Color(nsColor: .systemPurple))
                        .accessibilityLabel("Sandbox mode: test disks only")
                }
                Spacer()
                moreMenu
            }
            hero
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            ReclaimRing(content: ringContent, pulse: celebrations)
                .onGeometryChange(for: CGPoint.self, of: { proxy in
                    let frame = proxy.frame(in: .named(Self.space))
                    return CGPoint(x: frame.midX, y: frame.midY)
                }) { ringCenter = $0 }
            VStack(alignment: .leading, spacing: 2) {
                headline
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : Motion.easeOut(0.45), value: model.totalReclaimable)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let payoff {
                    payoff
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.top, 2)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }

    private var ringContent: ReclaimRing.Content {
        guard model.hasLoaded else { return .measuring }
        guard !model.drives.isEmpty else { return .idle }
        let reclaimable = model.totalReclaimable
        guard reclaimable > 0 else {
            return model.drives.contains(where: \.isMeasuring) ? .measuring : (model.needsFullDiskAccess ? .idle : .clear)
        }
        let free = model.emptiableDrives.reduce(Int64(0)) { $0 + $1.breakdown.free }
        return .reclaimable(fraction: Double(reclaimable) / Double(max(1, free + reclaimable)))
    }

    /// The amount, in Ember: it's the number the whole app is about.
    private var headline: some View {
        Group {
            if !model.hasLoaded {
                Text("Measuring…")
            } else if model.drives.isEmpty {
                Text("No drives")
            } else if model.totalReclaimable > 0 {
                Text(ByteFormat.string(model.totalReclaimable)).foregroundStyle(Brand.emberText)
            } else if model.drives.contains(where: \.isMeasuring) {
                Text("Measuring…")
            } else {
                Text("All clear")
            }
        }
    }

    private var subtitle: String {
        guard model.hasLoaded else { return "Looking at your drives" }
        guard !model.drives.isEmpty else { return "Nothing to measure yet." }
        let reclaimable = model.totalReclaimable
        guard reclaimable > 0 else {
            if model.needsFullDiskAccess { return "Nothing to reclaim on the drives Reclaim can see." }
            return "Every Trash is empty. Your boomerang’s resting."
        }
        let count = model.emptiableDrives.count
        return "ready to reclaim\(count > 1 ? " across \(count) drives" : "")"
    }

    /// "Free space 392 GB → 583 GB": what emptying gives back, on the drives it applies to.
    private var payoff: Text? {
        let drives = model.emptiableDrives
        guard model.hasLoaded, !drives.isEmpty else { return nil }
        let free = drives.reduce(Int64(0)) { $0 + $1.breakdown.free }
        let reclaimable = drives.reduce(Int64(0)) { $0 + $1.trash.totalBytes }
        return Text("Free space \(ByteFormat.string(free)) → ") + Text(ByteFormat.string(free + reclaimable)).fontWeight(.semibold)
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

    // MARK: Drives

    @ViewBuilder private var driveList: some View {
        if !model.hasLoaded {
            ForEach(0..<2, id: \.self) { _ in SkeletonCard() }
        } else if model.drives.isEmpty {
            Label(model.mode == .sandbox ? "Run Scripts/sandbox.sh up to attach the test disks."
                                         : "USB sticks, SD cards and external drives appear here when you plug them in.",
                  systemImage: "externaldrive.badge.plus")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()
        } else {
            ForEach(Array(model.drives.enumerated()), id: \.element.id) { index, state in
                DriveRow(model: model, state: state, index: index, showsLargestItems: expandedTrashPeeks.contains(state.id))
            }
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        VStack(spacing: 10) {
            if let notice = model.notice {
                NoticeView(notice: notice, dismiss: { withAnimation(Motion.easeOut(0.2)) { model.notice = nil } })
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
            emptyAllButton
        }
        .animation(reduceMotion ? nil : Motion.easeOut(0.25), value: model.notice?.id)
    }

    private var emptyAllButton: some View {
        let reclaimable = model.emptiableDrives.reduce(Int64(0)) { $0 + $1.trash.totalBytes }
        let enabled = !model.emptiableDrives.isEmpty && model.activity.isEmpty
        return Button {
            Task { await model.emptyAllTrash() }
        } label: {
            HStack {
                Text(model.settings.askBeforeEmptying ? "Empty All Trash…" : "Empty All Trash")
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                if reclaimable > 0 {
                    Text(ByteFormat.string(reclaimable))
                        .monospacedDigit()
                        .opacity(0.9)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(EmberButtonStyle())
        .disabled(!enabled)
        .help("Permanently erase the Trash on every drive")
    }
}

/// A placeholder card while the first measurement runs.
struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(Color(nsColor: .quaternaryLabelColor)).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(Color(nsColor: .quaternaryLabelColor)).frame(width: 110, height: 9)
                    Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.6)).frame(width: 150, height: 7)
                }
            }
            Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.6)).frame(height: 10)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .accessibilityHidden(true)
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
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous).fill(Color.accentColor.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

/// The result of the last action. Stays until dismissed (or the panel closes), so nobody has to
/// read it against a timer. When space came back it gets a small headline: the one place the app
/// is allowed to celebrate.
struct NoticeView: View {
    let notice: Notice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon.accessibilityHidden(true).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                if notice.reclaimedSpace {
                    Text("Boomerang’s back!")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Brand.emberText)
                }
                Text(notice.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        .padding(.leading, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                .fill(notice.reclaimedSpace ? Color(hex: 0xFF8F24).opacity(0.14) : Color(nsColor: .quaternarySystemFill))
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var icon: some View {
        if notice.reclaimedSpace {
            BoomerangShape()
                .fill(Brand.ember)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: notice.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(notice.kind == .success ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
        }
    }
}
