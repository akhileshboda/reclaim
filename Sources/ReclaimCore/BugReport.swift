import Foundation

/// A link to a new GitHub bug report with the versions already filled in, so testers don't have
/// to look them up. Only version numbers go in the URL, nothing about the user's files or drives.
public enum BugReport {
    public static func url(appVersion: String, macOSVersion: String) -> URL {
        var components = URLComponents(string: "https://github.com/\(UpdateChecker.repository)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "app-version", value: appVersion),
            URLQueryItem(name: "macos-version", value: macOSVersion),
        ]
        return components.url!
    }
}
