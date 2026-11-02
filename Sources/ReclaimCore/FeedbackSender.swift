import Foundation

public enum FeedbackResult: Sendable, Equatable {
    case sent
    case failed
}

/// Sends a typed report to the maintainer through a hosted form-to-email relay, so people can
/// report a problem without a GitHub account and without the recipient's address being in the app
/// or the repository. The relay's URL comes from the app's Info.plist, filled in at build time;
/// builds without one (local and development builds) don't offer this route at all.
///
/// Only what the person typed goes out, plus the Reclaim and macOS version numbers. Nothing about
/// their files or drives, and nothing is sent until they press Send.
public struct FeedbackSender: Sendable {
    public static let infoKey = "ReclaimFeedbackURL"
    public static let maxMessageLength = 5_000

    let endpoint: URL
    let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        endpoint: URL,
        fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) {
        self.endpoint = endpoint
        self.fetch = fetch
    }

    /// The sender configured by the build, or nil when the Info.plist has no usable `https` URL.
    public static func configured(
        infoDictionary: [String: Any]?,
        fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) -> FeedbackSender? {
        guard let text = (infoDictionary?[infoKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), url.scheme == "https", url.host != nil
        else { return nil }
        return FeedbackSender(endpoint: url, fetch: fetch)
    }

    /// `replyTo` is optional: it's passed on only when it looks like an email address.
    public func send(message: String, replyTo: String, appVersion: String, macOSVersion: String) async -> FeedbackResult {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failed }

        var fields: [String: String] = [
            "subject": "Reclaim \(appVersion) feedback",
            "message": String(text.prefix(Self.maxMessageLength)),
            "app_version": appVersion,
            "macos_version": macOSVersion,
        ]
        let contact = replyTo.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.looksLikeEmail(contact) { fields["email"] = contact }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])

        guard let (data, response) = try? await fetch(request),
              let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
        else { return .failed }
        // Relays answer 200 with a body saying whether the message was accepted.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["success"] as? Bool == false || json["ok"] as? Bool == false {
            return .failed
        }
        return .sent
    }

    static func looksLikeEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
            && !text.contains(where: \.isWhitespace) && text.count <= 254
    }
}
