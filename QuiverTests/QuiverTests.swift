import XCTest
@testable import Quiver

final class QuiverTests: XCTestCase {

    func testBoardEffectiveVolumeUsesUserValue() {
        let b = Board(type: .hpsb, lengthIn: 70, widthIn: 18.75, thicknessIn: 2.4, volumeL: 29.4)
        XCTAssertEqual(b.effectiveVolumeL, 29.4, accuracy: 0.0001)
    }

    func testBoardEffectiveVolumeFallsBackToGeometric() {
        let b = Board(type: .hpsb, lengthIn: 70, widthIn: 18.75, thicknessIn: 2.4, volumeL: nil)
        // 70 × 18.75 × 2.4 × 0.565 × 0.01639 = ~29.2 L
        XCTAssertEqual(b.effectiveVolumeL, 29.2, accuracy: 0.3)
    }

    func testLengthDisplayFormatsFeetAndInches() {
        XCTAssertEqual(Board(type: .hpsb, lengthIn: 70, widthIn: 18.75, thicknessIn: 2.4).lengthDisplay, "5'10\"")
        XCTAssertEqual(Board(type: .longboard, lengthIn: 108, widthIn: 23, thicknessIn: 3.0).lengthDisplay, "9'")
        XCTAssertEqual(Board(type: .midLength, lengthIn: 79.5, widthIn: 21, thicknessIn: 2.8).lengthDisplay, "6'7.5\"")
    }

    func testQuiverMatcherFallsBackToAnyBoardIfNoTypeMatches() {
        // User only owns a longboard but the recommendation is HPSB — matcher should still
        // surface the longboard as a best-effort.
        let onlyBoard = Board(nickname: "Cruiser", type: .longboard, lengthIn: 110, widthIn: 23, thicknessIn: 3.1, volumeL: 75)
        let matcher = QuiverMatcher()
        let matches = matcher.match(
            quiver: [onlyBoard],
            type: .hpsb,
            adjacent: [.groveler, .stepUp],
            targetVolume: VolumeRange(lowL: 29, highL: 31)
        )
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.board.nickname, "Cruiser")
    }

    func testVolumeCalculatorPrimitiveOverloadMatchesProfileOverload() {
        let calc = VolumeCalculator()
        let snap = ConditionsSnapshot(
            spotId: "x", timestamp: Date(), fetchedAt: Date(),
            swellHeightM: 1.2, swellPeriodS: 12, swellDirDeg: 270,
            waveHeightM: nil, wavePeriodS: nil, waveDirDeg: nil,
            windSpeedKt: 5, windDirDeg: 45, windGustKt: nil,
            tideHeightM: nil, tideTrend: nil,
            buoyWaveHeightM: nil, buoyDominantPeriodS: nil, buoyMeanDirDeg: nil
        )
        let profile = UserProfile(heightIn: 70, weightLb: 170, age: 30, gender: .preferNotToSay, skillLevel: .advanced)
        let fromProfile = calc.targetVolume(profile: profile, conditions: snap, advisory: nil)
        let fromPrimitive = calc.targetVolume(
            weightKg: profile.weightKg, skill: .advanced, age: 30,
            conditions: snap, advisory: nil
        )
        XCTAssertEqual(fromProfile.lowL, fromPrimitive.lowL, accuracy: 0.0001)
        XCTAssertEqual(fromProfile.highL, fromPrimitive.highL, accuracy: 0.0001)
    }

    func testConditionsPresetSnapshotsRoundTripThroughTypeSelector() {
        let selector = BoardTypeSelector()
        let spot = Spot(
            id: "x", name: "x", lat: 34, lon: -119, region: .sbSouth,
            ndbcBuoyId: nil, tideStationId: nil,
            optimalSwellDirMinDeg: 200, optimalSwellDirMaxDeg: 290,
            favorableWindDirMinDeg: 0, favorableWindDirMaxDeg: 90,
            notes: nil
        )
        // Small + intermediate → small-wave / forgiving family
        let small = selector.choose(
            conditions: ConditionsPreset.small.snapshot(spotId: "x"),
            spot: spot, skill: .intermediate
        )
        XCTAssertTrue([.groveler, .fish, .allRounder, .longboard, .midLength].contains(small.primary))

        // Big + expert → step-up or gun
        let big = selector.choose(
            conditions: ConditionsPreset.big.snapshot(spotId: "x"),
            spot: spot, skill: .expert
        )
        XCTAssertTrue([.stepUp, .gun].contains(big.primary))
    }
}
