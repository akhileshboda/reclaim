import AppKit
import SwiftUI
import ReclaimUI

/// `--capture <dir>`: the running app measures the real drives it can see (the RTEST-* disks in
/// sandbox mode), renders its own panel to PNG in light and dark, and quits. No Screen
/// Recording permission is involved because the app only draws its own views.
@MainActor
struct CaptureRunner {
    let model: AppModel
    let directory: URL

    func run() async {
        await model.refresh()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let largestTrash = model.drives.max { $0.trash.totalBytes < $1.trash.totalBytes }
            let variants: [(name: String, expanded: Set<String>)] = [
                ("app-panel", []),
                ("app-panel-peek", largestTrash.map { [$0.id] } ?? []),
            ]
            for variant in variants {
                for dark in [false, true] {
                    let view = PanelView(model: model, expandedTrashPeeks: variant.expanded)
                    guard let png = SnapshotRenderer.png(view, width: PanelView.width, dark: dark) else { continue }
                    let file = directory.appendingPathComponent("\(variant.name)-\(dark ? "dark" : "light").png")
                    try png.write(to: file)
                    print("captured \(file.path)")
                }
            }
        } catch {
            FileHandle.standardError.write(Data("capture failed: \(error)\n".utf8))
        }
        NSApp.terminate(nil)
    }
}
