import Testing
@testable import ReclaimCore

@Suite struct SpaceBreakdownTests {
    @Test func segmentsSumToTotal() {
        let b = SpaceBreakdown(total: 1_000, free: 200, importantFree: 350, trash: 100)
        #expect(b.free == 200)
        #expect(b.purgeable == 150)
        #expect(b.trash == 100)
        #expect(b.used == 550)
        #expect(b.used + b.trash + b.purgeable + b.free == b.total)
        #expect(b.reclaimable == 100)
        #expect(b.availableAfterCleanup == 450)
    }

    @Test func missingImportantUsageMeansNoPurgeable() {
        let b = SpaceBreakdown(total: 1_000, free: 300, importantFree: nil, trash: 50)
        #expect(b.purgeable == 0)
        #expect(b.used == 650)
    }

    @Test func importantUsageBelowFreeIsClampedToZero() {
        let b = SpaceBreakdown(total: 1_000, free: 300, importantFree: 250, trash: 0)
        #expect(b.purgeable == 0)
    }

    @Test func trashCannotExceedOccupiedSpace() {
        // e.g. hard links or a stale scan reporting more trash than the drive holds.
        let b = SpaceBreakdown(total: 1_000, free: 900, importantFree: 950, trash: 500)
        #expect(b.trash == 50)
        #expect(b.used == 0)
        #expect(b.used + b.trash + b.purgeable + b.free == 1_000)
    }

    @Test func zeroAndNegativeInputsAreSafe() {
        let b = SpaceBreakdown(total: 0, free: -5, importantFree: -1, trash: -10)
        #expect(b == SpaceBreakdown(total: 0, free: 0, importantFree: 0, trash: 0))
        #expect(b.fraction(of: b.used) == 0)
    }

    @Test func fractions() {
        let b = SpaceBreakdown(total: 400, free: 100, importantFree: 100, trash: 100)
        #expect(b.fraction(of: b.free) == 0.25)
        #expect(b.fraction(of: b.used) == 0.5)
    }
}

@Suite struct ByteFormatTests {
    @Test func badgeIsCompact() {
        #expect(ByteFormat.badge(4_200_000_000) == "4.2 GB")
        #expect(ByteFormat.badge(37_400_000_000) == "37 GB")
        #expect(ByteFormat.badge(999_700_000) == "1.0 GB")
        #expect(ByteFormat.badge(1_500_000_000_000) == "1.5 TB")
    }

    @Test func zeroIsNumeric() {
        #expect(!ByteFormat.string(0).lowercased().contains("zero"))
    }
}
