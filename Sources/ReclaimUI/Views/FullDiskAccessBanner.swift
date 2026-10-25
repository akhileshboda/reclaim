import SwiftUI

/// Explains why Reclaim needs Full Disk Access and links straight to the right Settings pane.
struct FullDiskAccessBanner: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(Color(nsColor: .systemOrange))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Allow access to your Mac’s Trash")
                    .font(.callout.weight(.semibold))
                Text("macOS protects the Trash on your startup disk. Turn on Reclaim in Full Disk Access so it can measure and empty it. Reclaim checks again when you come back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy & Security Settings…", action: openSettings)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .systemOrange).opacity(0.1)))
        .accessibilityElement(children: .contain)
    }
}
