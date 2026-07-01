import XCTest
@testable import Quiver

final class ForecastVolumeTests: XCTestCase {

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

    // 170 lb intermediate profile reused across tests.
    private let weightKg = 170.0 * 0.45359237
    private let skill = SkillLevel.intermediate
    private let age = 30

    func testOneEntryPerDayInAscendingOrder() {
        let s = spot()
        let cal = Calendar.current
        let day0 = cal.startOfDay(for: Date())
        var snaps: [ConditionsSnapshot] = []
        for dayOffset in 0..<3 {
            let dayStart = cal.date(byAdding: .day, value: dayOffset, to: day0)!
            for hour in [8, 12, 16] {
                let t = cal.date(byAdding: .hour, value: hour, to: dayStart)!
                snaps.append(snap(at: t, ft: 4, period: 12, windKt: 5, windDir: 45))
            }
        }
        let result = ForecastVolume.dailyMinimums(
            snapshots: snaps, spot: s, weightKg: weightKg, skill: skill, age: age, calendar: cal
        )
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.date), result.map(\.date).sorted())
    }

    func testRespectsMaxDays() {
        let s = spot()
        let cal = Calendar.current
        let day0 = cal.startOfDay(for: Date())
        var snaps: [ConditionsSnapshot] = []
        for dayOffset in 0..<10 {
            let t = cal.date(byAdding: .day, value: dayOffset, to: day0)!.addingTimeInterval(8 * 3600)
            snaps.append(snap(at: t, ft: 4, period: 12, windKt: 5, windDir: 45))
        }
        let result = ForecastVolume.dailyMinimums(
            snapshots: snaps, spot: s, weightKg: weightKg, skill: skill, age: age, calendar: cal, maxDays: 7
        )
        XCTAssertEqual(result.count, 7)
    }

    func testSmallDayHasHigherMinVolumeThanSolidDay() {
        let s = spot()
        let cal = Calendar.current
        let day0 = cal.startOfDay(for: Date())
        let day1 = cal.date(byAdding: .day, value: 1, to: day0)!

        // Day 0: small/weak surf → more float → higher minimum volume.
        let small = snap(at: day0.addingTimeInterval(8 * 3600), ft: 1.5, period: 8, windKt: 4, windDir: 45)
        // Day 1: solid/powerful clean surf → less float → lower minimum volume.
        let solid = snap(at: day1.addingTimeInterval(8 * 3600), ft: 6, period: 13, windKt: 4, windDir: 45)

        let result = ForecastVolume.dailyMinimums(
            snapshots: [small, solid], spot: s, weightKg: weightKg, skill: skill, age: age, calendar: cal
        )
        XCTAssertEqual(result.count, 2)
        let smallDay = result[0]
        let solidDay = result[1]
        XCTAssertGreaterThan(smallDay.minVolumeL, solidDay.minVolumeL)
    }

    func testPicksPeakQualityHourForTheDay() {
        let s = spot()
        let cal = Calendar.current
        let day0 = cal.startOfDay(for: Date())

        // One clean glassy hour (4 ft @ 13s, light offshore) amid blown-out hours.
        let glassy = snap(at: day0.addingTimeInterval(7 * 3600), ft: 4, period: 13, windKt: 3, windDir: 45)
        let blown1 = snap(at: day0.addingTimeInterval(12 * 3600), ft: 4, period: 13, windKt: 24, windDir: 225)
        let blown2 = snap(at: day0.addingTimeInterval(15 * 3600), ft: 4, period: 13, windKt: 26, windDir: 225)

        let result = ForecastVolume.dailyMinimums(
            snapshots: [blown1, glassy, blown2], spot: s, weightKg: weightKg, skill: skill, age: age, calendar: cal
        )
        let day = try! XCTUnwrap(result.first)
        // The chosen representative hour is the glassy one — which is clean (no advisory),
        // so its minimum volume is lower than if a blown hour (advisory adds float) were used.
        let blownAdvisoryResult = ForecastVolume.dailyMinimums(
            snapshots: [blown1, blown2], spot: s, weightKg: weightKg, skill: skill, age: age, calendar: cal
        )
        let blownDay = try! XCTUnwrap(blownAdvisoryResult.first)
        XCTAssertLessThan(day.minVolumeL, blownDay.minVolumeL)
    }

    func testEmptySnapshotsReturnsEmpty() {
        let result = ForecastVolume.dailyMinimums(
            snapshots: [], spot: spot(), weightKg: weightKg, skill: skill, age: age
        )
        XCTAssertTrue(result.isEmpty)
    }
}
