import SwiftUI

/// Explains why Reclaim needs Full Disk Access and links straight to the right Settings pane.
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
                Text("macOS protects the Trash on your startup disk. Turn on Reclaim in Full Disk Access so it can measure and empty it. Reclaim checks again when you come back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Open Privacy & Security Settings…", action: openSettings)
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
