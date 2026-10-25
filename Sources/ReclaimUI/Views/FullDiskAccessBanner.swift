import SwiftUI

/// Explains why Reclaim needs Full Disk Access and how to grant it. macOS doesn't list an app in
/// Full Disk Access by itself: the person has to add it with + (or drag it in), so the button
/// opens the pane and shows Reclaim in Finder at the same time.
struct FullDiskAccessBanner: View {
    let openSettings: () -> Void
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
                Text("Optional. macOS protects the Trash on your startup disk. In Full Disk Access, click +, choose Reclaim (or drag it in from Finder), turn it on, then reopen Reclaim. External drives work without this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Open Full Disk Access…", action: openSettings)
                    Button("Not Now", action: notNow)
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)))
        .accessibilityElement(children: .contain)
    }
}
