import Foundation

public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// Parses "1.2.3", "v1.2" or "1"; anything after a "-" or "+" (pre-release, build) is ignored.
    public init?(_ string: String) {
        var core = string.trimmingCharacters(in: .whitespaces)
        if core.hasPrefix("v") || core.hasPrefix("V") { core.removeFirst() }
        core = String(core.prefix { $0 != "-" && $0 != "+" })
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        major = parts[0]!
        minor = parts.count > 1 ? parts[1]! : 0
        patch = parts.count > 2 ? parts[2]! : 0
    }

    public static func < (a: Self, b: Self) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
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

/// Asks GitHub for the latest release. A missing repository or release (404), being offline, or
/// rate limiting all mean "no update information", never an error the user has to deal with.
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

    /// The newer release, or nil when up to date or when nothing could be determined.
    public func newerRelease() async -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        guard let (data, response) = try? await fetch(request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data)
        else { return nil }
        return Self.isNewer(release, than: currentVersion) ? release : nil
    }

    public static func isNewer(_ release: Release, than current: SemanticVersion) -> Bool {
        guard !release.draft, !release.prerelease, let version = release.version else { return false }
        return version > current
    }
}
