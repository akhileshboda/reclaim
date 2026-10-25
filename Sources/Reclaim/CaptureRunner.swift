import AppKit
import SwiftUI
import ReclaimUI

/// `--capture <dir>`: the running app measures the real drives it can see (the RTEST-* disks in
/// sandbox mode), renders its own panel and Settings panes to PNG in light and dark, and quits.
/// No Screen Recording permission is involved because the app only draws its own views.
@MainActor
struct CaptureRunner {
    let model: AppModel
    let services: SettingsServices
    let directory: URL

    func run() async {
        await model.refresh()
        let largestTrash = model.drives.max { $0.trash.totalBytes < $1.trash.totalBytes }
        let settings = model.settings
        let shots: [(name: String, width: CGFloat, view: AnyView)] = [
            ("app-panel", PanelView.width, AnyView(PanelView(model: model))),
            ("app-panel-peek", PanelView.width, AnyView(PanelView(model: model, expandedTrashPeeks: largestTrash.map { [$0.id] } ?? []))),
            ("app-settings-general", 500, AnyView(GeneralSettingsPane(settings: settings, services: services))),
            ("app-settings-cleaning", 500, AnyView(CleaningSettingsPane(settings: settings, services: services))),
            ("app-settings-notifications", 500, AnyView(NotificationsSettingsPane(settings: settings, services: services))),
        ]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for shot in shots {
                for dark in [false, true] {
                    guard let png = SnapshotRenderer.png(shot.view, width: shot.width, dark: dark) else { continue }
                    let file = directory.appendingPathComponent("\(shot.name)-\(dark ? "dark" : "light").png")
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
