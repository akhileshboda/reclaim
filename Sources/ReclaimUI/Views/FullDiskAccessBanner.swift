import SwiftUI

/// Explains why Reclaim needs Full Disk Access and how to grant it. Reclaim is already in the
/// list (macOS adds it the first time it is refused), so the person only has to switch it on.
struct FullDiskAccessBanner: View {
    /// True once the person has been sent to System Settings.
    let awaitingToggle: Bool
    let openSettings: () -> Void
    let restart: () -> Void
    let notNow: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Allow access to your Mac’s Trash")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if awaitingToggle {
                        Button("Restart Reclaim", action: restart)
                        Button("Open Again", action: openSettings)
                    } else {
                        Button("Open Full Disk Access…", action: openSettings)
                        Button("Not Now", action: notNow)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)))
        .accessibilityElement(children: .contain)
    }

    private var message: String {
        awaitingToggle
            ? "Turn on Reclaim in the list. macOS then offers to reopen it; if it doesn’t, restart Reclaim here. If Reclaim isn’t listed, click + and add it."
            : "Optional. macOS protects the Trash on your startup disk. Open Full Disk Access and turn on Reclaim. External drives work without this."
    }
}
