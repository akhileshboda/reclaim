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
    @Test(arguments: [("1.2.3", "1.2.3"), ("v0.1.0", "0.1.0"), ("2", "2.0.0"), ("1.4-beta.2", "1.4.0"), ("v3.1.0+build7", "3.1.0")])
    func parsesVersions(input: String, expected: String) {
        #expect(SemanticVersion(input)?.description == expected)
    }

    @Test(arguments: ["", "v", "1..2", "a.b.c", "1.2.3.4", "-1.0"])
    func rejectsGarbage(_ input: String) {
        #expect(SemanticVersion(input) == nil)
    }

    @Test func ordering() {
        #expect(SemanticVersion("0.10.0")! > SemanticVersion("0.9.9")!)
        #expect(SemanticVersion("1.0.0")! > SemanticVersion("0.99.99")!)
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
}
