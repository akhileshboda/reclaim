import Foundation
@testable import ReclaimCore

/// A throwaway directory tree that mimics a home folder and a /Volumes directory, created inside
/// the test sandbox (RECLAIM_SANDBOX_DIR when running under Scripts/run-sandboxed.sh).
final class Fixture {
    let root: URL
    let home: URL
    let volumes: URL
    let outside: URL
    let uid = getuid()

    init() throws {
        let base = ProcessInfo.processInfo.environment["RECLAIM_SANDBOX_DIR"] ?? NSTemporaryDirectory()
        let dir = URL(fileURLWithPath: base).appendingPathComponent("unit/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: Paths.canonical(dir.path)!, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        volumes = root.appendingPathComponent("Volumes", isDirectory: true)
        outside = root.appendingPathComponent("outside", isDirectory: true)
        for url in [home, volumes, outside] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    deinit {
        // Unlock anything a test locked so cleanup can't leave debris behind.
        TrashEmptier.unlockTree(at: root.path, canonicalRoot: (root.path as NSString).deletingLastPathComponent)
        try? FileManager.default.removeItem(at: root)
    }

    func policy(_ mode: RuntimeMode = .sandbox) -> SafetyPolicy {
        SafetyPolicy(mode: mode, homeDirectory: home, volumesDirectory: volumes, userID: uid)
    }

    func makeVolume(_ name: String) throws -> URL {
        let volume = volumes.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        return volume
    }

    func makeTrash(onVolume name: String) throws -> URL {
        let trash = try makeVolume(name).appendingPathComponent(".Trashes/\(uid)", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        return trash
    }

    @discardableResult
    func write(_ url: URL, bytes: Int) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: bytes).write(to: url)
        return url
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || Paths.isSymlink(url.path)
    }
}
