import CoreServices
import Foundation

/// Reports file-system changes under a set of folders (the drives' Trash folders) using FSEvents,
/// so Reclaim rescans a Trash only when something was actually moved into or out of it. Polling
/// instead would keep external hard drives from ever going to sleep.
public final class DirectoryWatcher: @unchecked Sendable {
    /// Called on the main queue with the paths FSEvents reported (coalesced over `latency`).
    public typealias Handler = @MainActor @Sendable ([String]) -> Void

    private let handler: Handler
    private let latency: TimeInterval
    // Only touched on the main thread.
    private var stream: FSEventStreamRef?
    private var watched: [String] = []

    public init(latency: TimeInterval = 1.5, handler: @escaping Handler) {
        self.latency = latency
        self.handler = handler
    }

    deinit {
        if let stream { Self.tearDown(stream) }
    }

    /// Starts watching exactly `paths` (replacing what was watched before). Main thread only.
    public func watch(_ paths: [String]) {
        let paths = paths.sorted()
        guard paths != watched else { return }
        stop()
        watched = paths
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
            MainActor.assumeIsolated { watcher.handler(paths) }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        if let stream { Self.tearDown(stream) }
        stream = nil
        watched = []
    }

    private static func tearDown(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
