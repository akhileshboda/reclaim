import Foundation

public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Dot-separated identifiers after the "-", e.g. ["beta", "2"]. Empty for a final release.
    public let prerelease: [String]

    /// Parses "1.2.3", "v1.2", "1" or "0.1.0-beta.2"; build metadata after a "+" is ignored.
    public init?(_ string: String) {
        var core = string.trimmingCharacters(in: .whitespaces)
        if core.hasPrefix("v") || core.hasPrefix("V") { core.removeFirst() }
        core = String(core.prefix { $0 != "+" })
        var prerelease: [String] = []
        if let dash = core.firstIndex(of: "-") {
            prerelease = core[core.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard prerelease.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } })
            else { return nil }
            core = String(core[..<dash])
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        major = parts[0]!
        minor = parts.count > 1 ? parts[1]! : 0
        patch = parts.count > 2 ? parts[2]! : 0
        self.prerelease = prerelease
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    /// Semantic Versioning precedence: a pre-release sorts before its final release
    /// (0.1.0-beta.2 < 0.1.0), and numeric identifiers compare as numbers (beta.2 < beta.11).
    public static func < (a: Self, b: Self) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) {
            return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
        switch (a.isPrerelease, b.isPrerelease) {
        case (false, _): return false
        case (true, false): return true
        case (true, true): break
        }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return x < y
            }
        }
        return a.prerelease.count < b.prerelease.count
    }

    public var description: String {
        "\(major).\(minor).\(patch)" + (isPrerelease ? "-" + prerelease.joined(separator: ".") : "")
    }
}

public struct Release: Decodable, Sendable, Equatable {
    public let tagName: String
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease
    }

    public var version: SemanticVersion? { SemanticVersion(tagName) }
}

public enum UpdateStatus: Sendable, Equatable {
    case available(Release)
    case upToDate
    /// Offline, rate-limited, or no published release yet: nothing reliable to report.
    case unknown
}

/// Asks GitHub for the latest release. A missing repository or release (404), being offline, or
/// rate limiting all mean "unknown", never an error the user has to deal with.
public struct UpdateChecker: Sendable {
    public static let repository = "akhileshboda/reclaim"

    public let currentVersion: SemanticVersion
    let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        currentVersion: SemanticVersion,
        fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) {
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    public var releasesPage: URL { URL(string: "https://github.com/\(Self.repository)/releases")! }

    /// Final builds ask for the latest final release. Beta builds also look at pre-releases, which
    /// GitHub's "latest" leaves out, so testers hear about the next beta and the final release.
    public func check() async -> UpdateStatus {
        let path = currentVersion.isPrerelease ? "releases?per_page=30" : "releases/latest"
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/\(path)")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        guard let (data, response) = try? await fetch(request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return .unknown }
        let releases: [Release]
        if currentVersion.isPrerelease {
            guard let list = try? JSONDecoder().decode([Release].self, from: data) else { return .unknown }
            releases = list
        } else {
            guard let latest = try? JSONDecoder().decode(Release.self, from: data) else { return .unknown }
            releases = [latest]
        }
        let newest = releases
            .filter { Self.isNewer($0, than: currentVersion) }
            .max { $0.version! < $1.version! }
        return newest.map { .available($0) } ?? .upToDate
    }

    /// The newer release, or nil when up to date or when nothing could be determined.
    public func newerRelease() async -> Release? {
        if case .available(let release) = await check() { return release }
        return nil
    }

    /// Pre-releases only count when the running build is one too: people on a final release
    /// are never moved onto a beta.
    public static func isNewer(_ release: Release, than current: SemanticVersion) -> Bool {
        guard !release.draft, let version = release.version else { return false }
        guard current.isPrerelease || !(release.prerelease || version.isPrerelease) else { return false }
        return version > current
    }
}
