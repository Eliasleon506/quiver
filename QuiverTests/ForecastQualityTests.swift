import XCTest
@testable import Quiver

final class ForecastQualityTests: XCTestCase {

    private func spot() -> Spot {
        Spot(
            id: "rincon-cove", name: "Rincon — Cove",
            lat: 34.37, lon: -119.47, region: .sbSouth,
            ndbcBuoyId: "46053", tideStationId: "9411340",
            optimalSwellDirMinDeg: 260, optimalSwellDirMaxDeg: 300,
            favorableWindDirMinDeg: 0, favorableWindDirMaxDeg: 90,
            notes: nil
        )
    }

    private func snap(
        at date: Date, ft: Double, period: Double, windKt: Double, windDir: Double, swellDir: Double = 275
    ) -> ConditionsSnapshot {
        ConditionsSnapshot(
            spotId: "rincon-cove", timestamp: date, fetchedAt: date,
            swellHeightM: ft / 3.28084, swellPeriodS: period, swellDirDeg: swellDir,
            waveHeightM: nil, wavePeriodS: nil, waveDirDeg: nil,
            windSpeedKt: windKt, windDirDeg: windDir, windGustKt: nil,
            tideHeightM: 1.0, tideTrend: .rising,
            buoyWaveHeightM: nil, buoyDominantPeriodS: nil, buoyMeanDirDeg: nil
        )
    }

    func testCleanAlignedSwellScoresHigherThanOnshoreSlop() {
        let s = spot()
        let now = Date()
        // Clean: 4 ft @ 13s, light offshore (45°, favorable 0..90), aligned swell.
        let clean = ForecastQuality.score(snap(at: now, ft: 4, period: 13, windKt: 4, windDir: 45), spot: s)
        // Slop: 1.5 ft @ 7s, onshore 25 kt from SW (225°), misaligned swell.
        let slop = ForecastQuality.score(snap(at: now, ft: 1.5, period: 7, windKt: 25, windDir: 225, swellDir: 180), spot: s)
        XCTAssertGreaterThan(clean, slop)
        XCTAssertGreaterThan(clean, 0.75)
        XCTAssertLessThan(slop, 0.45)
    }

    func testScoreIsClamped() {
        let s = spot()
        let v = ForecastQuality.score(snap(at: Date(), ft: 5, period: 16, windKt: 0, windDir: 45), spot: s)
        XCTAssertGreaterThanOrEqual(v, 0)
        XCTAssertLessThanOrEqual(v, 1)
    }

    func testBestWindowTodayPicksGlassyMorningOverWindyAfternoon() {
        let s = spot()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Build a day: glassy 7–9am, blown out 1–4pm.
        var snaps: [ConditionsSnapshot] = []
        for hour in 6...16 {
            let t = cal.date(byAdding: .hour, value: hour, to: today)!
            let glassyMorning = hour >= 7 && hour <= 9
            snaps.append(snap(
                at: t, ft: 4, period: 13,
                windKt: glassyMorning ? 3 : 22,
                windDir: glassyMorning ? 45 : 225,
                swellDir: 275
            ))
        }
        // Evaluate "now" as start of day so all hours are in the future window.
        let window = ForecastQuality.bestWindowToday(snaps, spot: s, now: today, calendar: cal)
        let w = try! XCTUnwrap(window)
        let startHour = cal.component(.hour, from: w.start)
        XCTAssertGreaterThanOrEqual(startHour, 7)
        XCTAssertLessThanOrEqual(startHour, 9)
        XCTAssertGreaterThan(w.peakScore, 0.7)
    }

    func testBestWindowReturnsNilWhenNoSnapshotsToday() {
        let s = spot()
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        let snaps = [snap(at: yesterday, ft: 4, period: 13, windKt: 4, windDir: 45)]
        XCTAssertNil(ForecastQuality.bestWindowToday(snaps, spot: s, now: Date(), calendar: cal))
    }

    func testLabelBuckets() {
        XCTAssertEqual(ForecastQuality.label(forScore: 0.1), "Poor")
        XCTAssertEqual(ForecastQuality.label(forScore: 0.5), "Fair")
        XCTAssertEqual(ForecastQuality.label(forScore: 0.6), "Good")
        XCTAssertEqual(ForecastQuality.label(forScore: 0.8), "Very good")
        XCTAssertEqual(ForecastQuality.label(forScore: 0.95), "Epic")
    }
}
