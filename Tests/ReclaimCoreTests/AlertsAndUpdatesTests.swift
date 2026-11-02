import Foundation
import Testing
@testable import ReclaimCore

@Suite struct LowSpaceTrackerTests {
    func drive(_ id: String, availablePercent: Double, trash: Int64 = 0, readOnly: Bool = false) -> (id: String, name: String, breakdown: SpaceBreakdown, isReadOnly: Bool) {
        let total: Int64 = 1_000_000_000
        let free = Int64(Double(total) * availablePercent / 100)
        return (id, id, SpaceBreakdown(total: total, free: free, importantFree: free, trash: trash), readOnly)
    }

    @Test func alertsOnceBelowThreshold() {
        var tracker = LowSpaceTracker(thresholdPercent: 10)
        let now = Date()
        #expect(tracker.evaluate([drive("A", availablePercent: 25)], now: now).isEmpty)
        #expect(tracker.evaluate([drive("A", availablePercent: 8)], now: now).map(\.driveID) == ["A"])
        #expect(tracker.evaluate([drive("A", availablePercent: 7)], now: now.addingTimeInterval(60)).isEmpty, "no nagging")
    }

    @Test func rearmsAfterRecoveringPastTheMargin() {
        var tracker = LowSpaceTracker(thresholdPercent: 10)
        let now = Date()
        _ = tracker.evaluate([drive("A", availablePercent: 5)], now: now)
        _ = tracker.evaluate([drive("A", availablePercent: 11)], now: now) // inside the margin: still armed-off
        #expect(tracker.evaluate([drive("A", availablePercent: 5)], now: now).isEmpty)
        _ = tracker.evaluate([drive("A", availablePercent: 13)], now: now) // recovered past 10 + 2
        #expect(tracker.evaluate([drive("A", availablePercent: 5)], now: now).count == 1)
    }

    @Test func repeatsAfterADay() {
        var tracker = LowSpaceTracker(thresholdPercent: 10)
        let now = Date()
        _ = tracker.evaluate([drive("A", availablePercent: 5)], now: now)
        #expect(tracker.evaluate([drive("A", availablePercent: 5)], now: now.addingTimeInterval(25 * 3600)).count == 1)
    }

    @Test func ignoresReadOnlyDrives() {
        var tracker = LowSpaceTracker(thresholdPercent: 10)
        #expect(tracker.evaluate([drive("A", availablePercent: 1, readOnly: true)]).isEmpty)
    }

    @Test func messageMentionsReclaimableTrash() {
        let alert = LowSpaceTracker.Alert(driveID: "A", driveName: "Footage SSD", availableBytes: 12_000_000_000, reclaimableBytes: 186_000_000_000)
        let message = LowSpaceTracker.message(for: alert)
        #expect(message.title == "“Footage SSD” Is Almost Full")
        #expect(message.body == "Only 12 GB is available. 186 GB is in its Trash.")
    }
}

@Suite struct UpdateCheckerTests {
    @Test(arguments: [("1.2.3", "1.2.3"), ("v0.1.0", "0.1.0"), ("2", "2.0.0"), ("1.4-beta.2", "1.4.0-beta.2"), ("v3.1.0+build7", "3.1.0"), ("v0.1.0-rc.1+abc", "0.1.0-rc.1")])
    func parsesVersions(input: String, expected: String) {
        #expect(SemanticVersion(input)?.description == expected)
    }

    @Test(arguments: ["", "v", "1..2", "a.b.c", "1.2.3.4", "-1.0", "1.0.0-", "1.0.0-beta..1", "1.0.0-bêta"])
    func rejectsGarbage(_ input: String) {
        #expect(SemanticVersion(input) == nil)
    }

    @Test func ordering() {
        #expect(SemanticVersion("0.10.0")! > SemanticVersion("0.9.9")!)
        #expect(SemanticVersion("1.0.0")! > SemanticVersion("0.99.99")!)
    }

    /// The precedence chain from the Semantic Versioning spec, section 11.
    @Test func prereleaseOrdering() {
        let chain = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
        let versions = chain.map { SemanticVersion($0)! }
        for (lower, higher) in zip(versions, versions.dropFirst()) {
            #expect(lower < higher, "\(lower) should sort before \(higher)")
            #expect(!(higher < lower))
        }
        #expect(SemanticVersion("0.1.0-beta.1")! > SemanticVersion("0.0.9")!)
        #expect(SemanticVersion("0.1.0+build1")! == SemanticVersion("0.1.0")!)
    }

    func response(_ status: Int, _ json: String) -> @Sendable (URLRequest) async throws -> (Data, URLResponse) {
        { request in
            (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test func reportsNewerStableRelease() async {
        let json = #"{"tag_name":"v0.2.0","html_url":"https://github.com/akhileshboda/reclaim/releases/tag/v0.2.0","draft":false,"prerelease":false}"#
        let checker = UpdateChecker(currentVersion: SemanticVersion("0.1.0")!, fetch: response(200, json))
        #expect(await checker.newerRelease()?.tagName == "v0.2.0")
    }

    @Test func distinguishesUpToDateFromUnknown() async {
        let current = SemanticVersion("0.1.0")!
        let same = #"{"tag_name":"v0.1.0","html_url":"https://example.com","draft":false,"prerelease":false}"#
        #expect(await UpdateChecker(currentVersion: current, fetch: response(200, same)).check() == .upToDate)
        #expect(await UpdateChecker(currentVersion: current, fetch: response(404, "{}")).check() == .unknown)
        #expect(await UpdateChecker(currentVersion: current, fetch: { _ in throw URLError(.timedOut) }).check() == .unknown)
    }

    @Test func ignoresOlderPrereleaseAndMissing() async {
        let older = #"{"tag_name":"v0.0.9","html_url":"https://example.com","draft":false,"prerelease":false}"#
        let pre = #"{"tag_name":"v9.0.0","html_url":"https://example.com","draft":false,"prerelease":true}"#
        let current = SemanticVersion("0.1.0")!
        #expect(await UpdateChecker(currentVersion: current, fetch: response(200, older)).newerRelease() == nil)
        #expect(await UpdateChecker(currentVersion: current, fetch: response(200, pre)).newerRelease() == nil)
        #expect(await UpdateChecker(currentVersion: current, fetch: response(404, #"{"message":"Not Found"}"#)).newerRelease() == nil)
        #expect(await UpdateChecker(currentVersion: current, fetch: { _ in throw URLError(.notConnectedToInternet) }).newerRelease() == nil)
    }

    func release(_ tag: String, prerelease: Bool = false, draft: Bool = false) -> String {
        #"{"tag_name":"\#(tag)","html_url":"https://example.com/\#(tag)","draft":\#(draft),"prerelease":\#(prerelease)}"#
    }

    /// Records which URL was asked for, so tests can tell the two release channels apart.
    final class Requests: @unchecked Sendable { var urls: [URL] = [] }

    @Test func finalBuildsAskForLatestOnly() async {
        let requests = Requests()
        let json = release("v0.2.0")
        let checker = UpdateChecker(currentVersion: SemanticVersion("0.1.0")!) { request in
            requests.urls.append(request.url!)
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(await checker.newerRelease()?.tagName == "v0.2.0")
        #expect(requests.urls.map(\.path) == ["/repos/akhileshboda/reclaim/releases/latest"])
    }

    @Test func finalBuildsIgnoreTagsThatLookLikePrereleases() async {
        // A pre-release tag published without GitHub's pre-release flag still isn't offered.
        let checker = UpdateChecker(currentVersion: SemanticVersion("0.1.0")!, fetch: response(200, release("v0.2.0-beta.1")))
        #expect(await checker.check() == .upToDate)
    }

    @Test func betaBuildsSeeTheNextBeta() async {
        let requests = Requests()
        let json = "[\(release("v0.1.0-beta.2", prerelease: true)),\(release("v0.1.0-beta.1", prerelease: true))]"
        let checker = UpdateChecker(currentVersion: SemanticVersion("0.1.0-beta.1")!) { request in
            requests.urls.append(request.url!)
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(await checker.newerRelease()?.tagName == "v0.1.0-beta.2")
        #expect(requests.urls.map(\.path) == ["/repos/akhileshboda/reclaim/releases"])
    }

    @Test func betaBuildsSeeTheFinalReleaseAndPickTheNewest() async {
        let json = "[\(release("v0.2.0-beta.1", draft: true)),\(release("v0.1.0")),\(release("v0.1.0-beta.3", prerelease: true)),\(release("not-a-version"))]"
        let checker = UpdateChecker(currentVersion: SemanticVersion("0.1.0-beta.2")!, fetch: response(200, json))
        #expect(await checker.newerRelease()?.tagName == "v0.1.0")
    }

    @Test func betaBuildsUpToDateAndUnknown() async {
        let current = SemanticVersion("0.1.0-beta.2")!
        let json = "[\(release("v0.1.0-beta.2", prerelease: true)),\(release("v0.1.0-beta.1", prerelease: true))]"
        #expect(await UpdateChecker(currentVersion: current, fetch: response(200, json)).check() == .upToDate)
        #expect(await UpdateChecker(currentVersion: current, fetch: response(200, "[]")).check() == .upToDate)
        #expect(await UpdateChecker(currentVersion: current, fetch: response(200, release("v0.1.0"))).check() == .unknown)
        #expect(await UpdateChecker(currentVersion: current, fetch: response(403, "{}")).check() == .unknown)
    }
}

@Suite struct BugReportTests {
    @Test func prefillsVersionsAndNothingElse() throws {
        let url = BugReport.url(appVersion: "0.1.0-beta.1", macOSVersion: "15.6.1")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "github.com")
        #expect(components.path == "/akhileshboda/reclaim/issues/new")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items == ["template": "bug_report.yml", "app-version": "0.1.0-beta.1", "macos-version": "15.6.1"])
    }

    /// The prefill keys must match the issue form's field ids, or GitHub silently ignores them.
    @Test func keysMatchTheIssueForm() throws {
        let form = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".github/ISSUE_TEMPLATE/bug_report.yml")
        let yaml = try String(contentsOf: form, encoding: .utf8)
        #expect(yaml.contains("id: app-version"))
        #expect(yaml.contains("id: macos-version"))
    }
}
