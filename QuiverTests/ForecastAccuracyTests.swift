import XCTest
@testable import Quiver

/// Pure-math tests for the forecast-verification harness (`ForecastAccuracy`). No SwiftData context
/// or network: `ForecastRecord`s are built in-memory and graded directly.
final class ForecastAccuracyTests: XCTestCase {

    private func record(
        spot: String = "rincon-cove",
        predM: Double,
        actualM: Double?,
        predPeriod: Double? = nil,
        actualPeriod: Double? = nil,
        leadHours: Double = 24
    ) -> ForecastRecord {
        let now = Date()
        let r = ForecastRecord(
            spotId: spot,
            validTime: now.addingTimeInterval(leadHours * 3600),
            recordedAt: now,
            predictedWaveHeightM: predM,
            predictedPeriodS: predPeriod
        )
        if let actualM {
            r.actualWaveHeightM = actualM
            r.actualPeriodS = actualPeriod
            r.isResolved = true
        }
        return r
    }

    func testEmptyWhenNoResolvedSamples() {
        let recs = [record(predM: 1.5, actualM: nil)]   // still pending
        XCTAssertEqual(ForecastAccuracy.summarize(recs), .empty)
    }

    func testMAEAndBiasInFeet() {
        // err1 = 0 m; err2 = +1.0 m ⇒ +3.28084 ft. MAE = bias = 1.640 ft.
        let recs = [
            record(predM: 1.0, actualM: 1.0),
            record(predM: 2.0, actualM: 1.0)
        ]
        let s = ForecastAccuracy.summarize(recs)
        XCTAssertEqual(s.sampleCount, 2)
        XCTAssertEqual(s.waveHeightMAEft, 1.640, accuracy: 1e-3)
        XCTAssertEqual(s.waveHeightBiasFt, 1.640, accuracy: 1e-3)
    }

    func testBiasIsSignedWhileMAEIsNot() {
        // Under-forecast then over-forecast by the same amount ⇒ bias ~0, MAE > 0.
        let recs = [
            record(predM: 0.5, actualM: 1.0),   // -0.5 m
            record(predM: 1.5, actualM: 1.0)    // +0.5 m
        ]
        let s = ForecastAccuracy.summarize(recs)
        XCTAssertEqual(s.waveHeightBiasFt, 0.0, accuracy: 1e-6)
        XCTAssertGreaterThan(s.waveHeightMAEft, 0.5)
    }

    func testPendingRecordsAreIgnored() {
        let recs = [
            record(predM: 2.0, actualM: 1.0),
            record(predM: 9.0, actualM: nil)    // pending — must not skew the stats
        ]
        XCTAssertEqual(ForecastAccuracy.summarize(recs).sampleCount, 1)
    }

    func testPeriodErrorOnlyCountsBothPresent() {
        let recs = [
            record(predM: 1.0, actualM: 1.0, predPeriod: 12, actualPeriod: 10),  // |2|
            record(predM: 1.0, actualM: 1.0)                                     // no period
        ]
        let s = ForecastAccuracy.summarize(recs)
        XCTAssertEqual(s.periodSampleCount, 1)
        XCTAssertEqual(s.periodMAEs, 2.0, accuracy: 1e-6)
    }

    func testBySpotGroupsAndDropsEmpty() {
        let recs = [
            record(spot: "rincon-cove", predM: 1.0, actualM: 1.0),
            record(spot: "jalama", predM: 2.0, actualM: 1.0),
            record(spot: "jaco", predM: 5.0, actualM: nil)   // pending only ⇒ dropped
        ]
        let bySpot = ForecastAccuracy.bySpot(recs)
        XCTAssertEqual(bySpot.map(\.spotId), ["jalama", "rincon-cove"])   // sorted, jaco dropped
    }
}
