import XCTest
@testable import HermesMobile

final class WorkFeatureTests: XCTestCase {
    func testRunsIsTheDefaultSegment() {
        XCTAssertEqual(
            WorkFeature.defaultSegment,
            .runs,
            "Runs answers 'what is happening right now?', which is why Work gets opened"
        )
    }

    func testStoredSegmentRoundTripsEverySegment() {
        for segment in WorkSegment.allCases {
            XCTAssertEqual(WorkFeature.storedSegment(segment.rawValue), segment)
        }
    }

    /// A raw value from a build that had a different segment set, or corrupt
    /// defaults, must fall back rather than crash or show nothing.
    func testUnknownOrMissingRawValueFallsBack() {
        XCTAssertEqual(WorkFeature.storedSegment(nil), WorkFeature.defaultSegment)
        XCTAssertEqual(WorkFeature.storedSegment(""), WorkFeature.defaultSegment)
        XCTAssertEqual(WorkFeature.storedSegment("timeline"), WorkFeature.defaultSegment)
    }

    /// Raw values are persisted, so renaming one silently resets every user's
    /// remembered segment. This pins them.
    func testRawValuesAreStableStorageIdentifiers() {
        XCTAssertEqual(WorkSegment.runs.rawValue, "runs")
        XCTAssertEqual(WorkSegment.board.rawValue, "board")
        XCTAssertEqual(WorkSegment.schedules.rawValue, "schedules")
    }

    func testRememberedSegmentIsHonouredWhenNothingIsWaiting() {
        XCTAssertEqual(
            WorkFeature.openingSegment(remembered: .schedules, hasWaitingRun: false),
            .schedules
        )
    }

    /// PRODUCT.md: if an approval is pending, Work opens to the affected run.
    func testAWaitingRunOverridesTheRememberedSegment() {
        XCTAssertEqual(
            WorkFeature.openingSegment(remembered: .schedules, hasWaitingRun: true),
            .runs,
            "attention beats habit"
        )
    }

    func testWorkIsOffByDefaultSoIncompleteUIStaysHidden() {
        // The flag key must exist and be distinct from the segment key, or
        // enabling Work would clobber the remembered segment.
        XCTAssertNotEqual(WorkFeature.isEnabledKey, WorkFeature.lastSegmentKey)
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: WorkFeature.isEnabledKey),
            "Work must default to off per the ROADMAP release policy"
        )
    }

    func testEverySegmentHasANonEmptyTitle() {
        for segment in WorkSegment.allCases {
            XCTAssertFalse(
                segment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(segment.rawValue) has no label"
            )
        }
    }
}
