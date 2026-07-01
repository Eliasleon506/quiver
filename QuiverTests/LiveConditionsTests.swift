import XCTest
@testable import Quiver

/// Hits the real APIs. Skipped by default — flip `runLive` to true to exercise.
final class LiveConditionsTests: XCTestCase {
    private let runLive = false

    func testLiveRinconAllProviders() async throws {
        try XCTSkipUnless(runLive, "Live network test disabled by default.")
        let rincon = Spot(
            id: "rincon-cove", name: "Rincon — Cove",
            lat: 34.3705, lon: -119.4731, region: .sbSouth,
            ndbcBuoyId: "46053", tideStationId: "9411340",
            optimalSwellDirMinDeg: 260, optimalSwellDirMaxDeg: 300,
            favorableWindDirMinDeg: 0, favorableWindDirMaxDeg: 90,
            notes: nil
        )
        let provider = CompositeConditionsProvider()
        let snap = try await provider.currentConditions(spot: rincon)
        XCTAssertNotNil(snap.primarySwellHeightFt)
        XCTAssertNotNil(snap.windSpeedKt)
    }
}
