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
            for dark in [false, true] {
                guard let png = SnapshotRenderer.png(PanelView(model: model), width: PanelView.width, dark: dark) else { continue }
                let file = directory.appendingPathComponent("app-panel-\(dark ? "dark" : "light").png")
                try png.write(to: file)
                print("captured \(file.path)")
            }
        } catch {
            FileHandle.standardError.write(Data("capture failed: \(error)\n".utf8))
        }
        NSApp.terminate(nil)
    }
}
