import Testing
@testable import ReclaimCore

@Suite struct RuntimeModeTests {
    @Test func defaultsToLive() {
        #expect(RuntimeMode.detect(arguments: ["Reclaim"], environment: [:]) == .live)
    }

    @Test func sandboxFromArgument() {
        #expect(RuntimeMode.detect(arguments: ["Reclaim", "--sandbox"], environment: [:]) == .sandbox)
    }

    @Test func sandboxFromEnvironment() {
        #expect(RuntimeMode.detect(arguments: ["Reclaim"], environment: ["RECLAIM_SANDBOX": "1"]) == .sandbox)
    }
}
