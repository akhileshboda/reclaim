// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Reclaim",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Reclaim", targets: ["Reclaim"]),
    ],
    targets: [
        // Pure logic: volumes, space accounting, trash scanning/emptying, junk cleanup, safety policy.
        .target(name: "ReclaimCore"),
        // SwiftUI views and the observable app model. A library so tests can render and drive it headlessly.
        .target(name: "ReclaimUI", dependencies: ["ReclaimCore"]),
        // AppKit shell: status item, popover, hotkey, alerts, notifications.
        .executableTarget(name: "Reclaim", dependencies: ["ReclaimCore", "ReclaimUI"]),
        .testTarget(name: "ReclaimCoreTests", dependencies: ["ReclaimCore"]),
        .testTarget(name: "ReclaimUITests", dependencies: ["ReclaimCore", "ReclaimUI"]),
    ]
)
