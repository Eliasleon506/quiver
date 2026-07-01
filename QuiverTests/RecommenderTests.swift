import XCTest
import SwiftData
@testable import Quiver

final class RecommenderTests: XCTestCase {

    // MARK: fixtures

    private func spot(
        id: String = "rincon-cove",
        optimalMin: Double = 260,
        optimalMax: Double = 300,
        character: WaveCharacter = .performancePoint,
        tide: TidePreference = .lowToMid
    ) -> Spot {
        Spot(
            id: id, name: id,
            lat: 34.37, lon: -119.47, region: .sbSouth,
            ndbcBuoyId: "46053", tideStationId: "9411340",
            optimalSwellDirMinDeg: optimalMin, optimalSwellDirMaxDeg: optimalMax,
            favorableWindDirMinDeg: 0, favorableWindDirMaxDeg: 90,
            waveCharacter: character, tidePreference: tide,
            notes: nil
        )
    }

    private func conditions(
        waveFt: Double, period: Double,
        windKt: Double = 5, windDirDeg: Double = 45,
        swellDir: Double = 280, tideFt: Double = 3.0
    ) -> ConditionsSnapshot {
        ConditionsSnapshot(
            spotId: "rincon-cove",
            timestamp: Date(), fetchedAt: Date(),
            swellHeightM: waveFt / 3.28084,
            swellPeriodS: period,
            swellDirDeg: swellDir,
            waveHeightM: nil, wavePeriodS: nil, waveDirDeg: nil,
            windSpeedKt: windKt, windDirDeg: windDirDeg, windGustKt: nil,
            tideHeightM: tideFt / 3.28084, tideTrend: .rising,
            buoyWaveHeightM: nil, buoyDominantPeriodS: nil, buoyMeanDirDeg: nil
        )
    }

    private func profile(weightLb: Double, skill: SkillLevel, age: Int = 30, heightIn: Double = 70) -> UserProfile {
        UserProfile(heightIn: heightIn, weightLb: weightLb, age: age, gender: .preferNotToSay, skillLevel: skill)
    }

    // MARK: reconciled core tests

    func testHeadHighCleanIntermediate_PerformanceBoard() {
        let rec = Recommender().recommend(
            profile: profile(weightLb: 170, skill: .intermediate),
            spot: spot(),
            conditions: conditions(waveFt: 4, period: 12),
            quiver: []
        )
        XCTAssertTrue([.shortboard, .hpsb, .allRounder].contains(rec.primaryType), "got \(rec.primaryType)")
        XCTAssertNil(rec.advisory)
        XCTAssertGreaterThan(rec.targetVolume.lowL, 30)
        XCTAssertLessThan(rec.targetVolume.highL, 50)
    }

    func testTinyMushyBeginner_LongboardWithExtraFloat() {
        let rec = Recommender().recommend(
            profile: profile(weightLb: 200, skill: .beginner),
            spot: spot(),
            conditions: conditions(waveFt: 1.5, period: 8),
            quiver: []
        )
        XCTAssertEqual(rec.primaryType, .longboard)
        XCTAssertGreaterThan(rec.targetVolume.lowL, 75)
    }

    func testHugeSurfBeginner_AdvisoryAndNotGun() {
        let rec = Recommender().recommend(
            profile: profile(weightLb: 160, skill: .beginner),
            spot: spot(),
            conditions: conditions(waveFt: 10, period: 15, windKt: 22, windDirDeg: 180),
            quiver: []
        )
        XCTAssertNotNil(rec.advisory)
        XCTAssertNotEqual(rec.primaryType, .gun, "Gun must be gated to advanced/expert")
    }

    func testElderlyIntermediate_AgeBumpsVolume() {
        let r = Recommender()
        let young = r.recommend(profile: profile(weightLb: 170, skill: .intermediate, age: 30),
                                spot: spot(), conditions: conditions(waveFt: 4, period: 12), quiver: [])
        let old = r.recommend(profile: profile(weightLb: 170, skill: .intermediate, age: 60),
                              spot: spot(), conditions: conditions(waveFt: 4, period: 12), quiver: [])
        XCTAssertGreaterThan(old.targetVolume.midpointL, young.targetVolume.midpointL)
    }

    func testOnshoreWind_TriggersAdvisoryButStillRecommends() {
        let rec = Recommender().recommend(
            profile: profile(weightLb: 170, skill: .intermediate),
            spot: spot(),
            conditions: conditions(waveFt: 3, period: 8, windKt: 14, windDirDeg: 225),
            quiver: []
        )
        XCTAssertNotNil(rec.advisory)
        XCTAssertTrue([.midLength, .funboard, .longboard, .groveler].contains(rec.primaryType))
    }

    func testQuiverMatchPicksClosestVolumeOfRightType() {
        let bigFish = Board(nickname: "Big fish", type: .fish, lengthIn: 66, widthIn: 21, thicknessIn: 2.7, volumeL: 38)
        let goodHPSB = Board(nickname: "Ghost", type: .hpsb, lengthIn: 70, widthIn: 18.75, thicknessIn: 2.4, volumeL: 29.4)
        let bigBoat = Board(nickname: "Boat", type: .longboard, lengthIn: 110, widthIn: 23, thicknessIn: 3.1, volumeL: 75)
        let rec = Recommender().recommend(
            profile: profile(weightLb: 170, skill: .intermediate),
            spot: spot(),
            conditions: conditions(waveFt: 4, period: 12),
            quiver: [bigFish, goodHPSB, bigBoat]
        )
        XCTAssertTrue([.shortboard, .hpsb, .allRounder].contains(rec.primaryType))
        XCTAssertEqual(rec.quiverMatches.first?.board.nickname, "Ghost")
    }

    // MARK: Gemini spec cases

    func testGoletaLocal_AverageConditions() {
        // 165 lb Advanced, <40 | 3–4 ft, 11s, 270° at a performance point (260–290°).
        let rec = Recommender().recommend(
            profile: profile(weightLb: 165, skill: .advanced, age: 30, heightIn: 70),
            spot: spot(id: "sands", optimalMin: 260, optimalMax: 290, character: .performancePoint, tide: .allTides),
            conditions: conditions(waveFt: 3.5, period: 11, swellDir: 270),
            quiver: []
        )
        XCTAssertTrue([.allRounder, .shortboard, .hpsb].contains(rec.primaryType), "got \(rec.primaryType)")
        XCTAssertNil(rec.advisory)
        XCTAssertGreaterThan(rec.targetVolume.lowL, 24)
        XCTAssertLessThan(rec.targetVolume.highL, 36)
        // Dimensions must be physically sane (no 4'2" HPSB).
        XCTAssertGreaterThanOrEqual(rec.dimensionSuggestion.lengthIn, 60)
        XCTAssertLessThanOrEqual(rec.dimensionSuggestion.lengthIn, 84)
    }

    func testRinconDad_SmallConditions() {
        let r = Recommender()
        let rincon = spot(id: "rincon-cove", optimalMin: 260, optimalMax: 300)
        let dad = r.recommend(profile: profile(weightLb: 190, skill: .advanced, age: 45),
                              spot: rincon, conditions: conditions(waveFt: 2, period: 8), quiver: [])
        XCTAssertTrue([.groveler, .fish, .allRounder].contains(dad.primaryType), "got \(dad.primaryType)")
        // Age 45 (M_age 1.04) lands above a 30-year-old's volume.
        let young = r.recommend(profile: profile(weightLb: 190, skill: .advanced, age: 30),
                                spot: rincon, conditions: conditions(waveFt: 2, period: 8), quiver: [])
        XCTAssertGreaterThan(dad.targetVolume.midpointL, young.targetVolume.midpointL)
    }

    func testIslandShadowing_BlockedSouthSwell() {
        // 6 ft, 14s, 190° (south) at Rincon (260–300°) → islands block it → ~1 ft flat.
        let rec = Recommender().recommend(
            profile: profile(weightLb: 175, skill: .intermediate, age: 30),
            spot: spot(id: "rincon-cove", optimalMin: 260, optimalMax: 300),
            conditions: conditions(waveFt: 6, period: 14, swellDir: 190),
            quiver: []
        )
        XCTAssertTrue([.longboard, .midLength].contains(rec.primaryType), "got \(rec.primaryType)")
        XCTAssertEqual(rec.advisory?.title, "Swell Shadowed")
    }

    func testTideSwamping() {
        let r = Recommender()
        let swampy = spot(id: "drainer", optimalMin: 260, optimalMax: 300, character: .performancePoint, tide: .lowToMid)
        let neutral = spot(id: "anytide", optimalMin: 260, optimalMax: 300, character: .performancePoint, tide: .allTides)
        let p = profile(weightLb: 175, skill: .advanced)
        let clean = conditions(waveFt: 3, period: 12, windKt: 2, swellDir: 280, tideFt: 5.0)

        let swamped = r.recommend(profile: p, spot: swampy, conditions: clean, quiver: [])
        let baseline = r.recommend(profile: p, spot: neutral, conditions: clean, quiver: [])

        XCTAssertEqual(swamped.advisory?.title, "Tide Swamped")
        XCTAssertGreaterThan(swamped.targetVolume.midpointL, baseline.targetVolume.midpointL)
    }

    // MARK: focused unit tests for new pieces

    func testDegreesOutsideWindow_WithWrap() {
        let s = spot(optimalMin: 260, optimalMax: 300)
        XCTAssertEqual(s.degreesOutsideWindow(280), 0, accuracy: 0.001)        // inside
        XCTAssertEqual(s.degreesOutsideWindow(250), 10, accuracy: 0.001)       // 10° below min
        XCTAssertEqual(s.degreesOutsideWindow(190), 70, accuracy: 0.001)       // far outside

        let wrap = spot(optimalMin: 350, optimalMax: 20)                       // window crosses 0°
        XCTAssertEqual(wrap.degreesOutsideWindow(5), 0, accuracy: 0.001)       // inside via wrap
        XCTAssertEqual(wrap.degreesOutsideWindow(40), 20, accuracy: 0.001)     // 20° past max
    }

    func testDimensionClamp_NoImpossiblyShortHPSB() {
        // A light expert wanting a tiny volume must not get a 4'2" HPSB.
        let builder = DimensionBuilder()
        let s = builder.suggest(type: .hpsb, skill: .expert,
                                targetVolume: VolumeRange(lowL: 21, highL: 23),
                                userHeightIn: 66, userWeightLb: 140)
        XCTAssertGreaterThanOrEqual(s.lengthIn, 60, "HPSB length must stay physically sane")
        XCTAssertGreaterThanOrEqual(s.widthIn, 18.25)
        XCTAssertLessThanOrEqual(s.thicknessIn, 3.5)
    }

    func testDimensionRoundTrip_BackToTargetVolume() {
        let builder = DimensionBuilder()
        let target = VolumeRange(lowL: 29.0, highL: 30.5)
        let suggestion = builder.suggest(type: .hpsb, skill: .advanced, targetVolume: target,
                                         userHeightIn: 70, userWeightLb: 170)
        XCTAssertEqual(suggestion.volumeL, target.midpointL, accuracy: 1.5)
        XCTAssertEqual((suggestion.lengthIn * 2).rounded(), suggestion.lengthIn * 2, accuracy: 0.001)
    }

    func testLongboardIgnoresShortboardVolumeTarget() {
        // Skilled light surfer on a tiny day: recommended longboard, but volume target is ~33 L.
        // Must yield a real plank, not a 15"-wide longboard.
        let s = DimensionBuilder().suggest(
            type: .longboard, skill: .advanced,
            targetVolume: VolumeRange(lowL: 30, highL: 35),
            userHeightIn: 68, userWeightLb: 140
        )
        XCTAssertGreaterThanOrEqual(s.lengthIn, 102)              // ≥ 8'6"
        XCTAssertGreaterThanOrEqual(s.widthIn, 22.0)
        XCTAssertLessThanOrEqual(s.widthIn, 23.0)
        XCTAssertGreaterThan(s.volumeL, 60)                       // floats naturally
    }

    func testLongboardLengthScalesWithWeight() {
        let b = DimensionBuilder()
        let light = b.suggest(type: .longboard, skill: .intermediate,
                              targetVolume: VolumeRange(lowL: 40, highL: 45), userHeightIn: 68, userWeightLb: 140)
        let heavy = b.suggest(type: .longboard, skill: .intermediate,
                              targetVolume: VolumeRange(lowL: 40, highL: 45), userHeightIn: 68, userWeightLb: 200)
        XCTAssertLessThan(light.lengthIn, heavy.lengthIn)
    }

    func testMidLengthEnforcesWidthAndThicknessFloor() {
        // A mid-length forced toward a shortboard volume must not go skinny.
        let s = DimensionBuilder().suggest(
            type: .midLength, skill: .advanced,
            targetVolume: VolumeRange(lowL: 36, highL: 40),
            userHeightIn: 70, userWeightLb: 170
        )
        XCTAssertGreaterThanOrEqual(s.widthIn, 20.5)
        XCTAssertGreaterThanOrEqual(s.thicknessIn, 2.5)
    }

    func testAdvisoryPriorityResolution() {
        let info = AdvisoryFactory.swellShadowed()
        let severe = AdvisoryFactory.blownOut(windKt: 18)
        let danger = AdvisoryFactory.aboveSkillLevel()
        XCTAssertEqual(AdvisoryFactory.resolve([info, severe, danger])?.title, danger.title)
        XCTAssertEqual(AdvisoryFactory.resolve([info, severe])?.title, severe.title)
        XCTAssertEqual(AdvisoryFactory.resolve([AdvisoryFactory.tideSwamped(), info])?.severity, .informational)
        XCTAssertNil(AdvisoryFactory.resolve([]))
    }

    // MARK: skill quiz — additive 110-point scorer

    /// Build an Answers from an explicit [Q: option index] map.
    private func answers(_ map: [SkillQuiz.Q: Int]) -> SkillQuiz.Answers {
        var ans = SkillQuiz.Answers()
        for (q, idx) in map { ans.values[q.rawValue] = idx }
        return ans
    }

    /// All questions at their top (max-points) option, with optional per-question overrides.
    private func maxAnswers(overriding overrides: [SkillQuiz.Q: Int] = [:]) -> SkillQuiz.Answers {
        var ans = SkillQuiz.Answers()
        for q in SkillQuiz.Q.allCases { ans.values[q.rawValue] = q.options.count - 1 }
        for (q, idx) in overrides { ans.values[q.rawValue] = idx }
        return ans
    }

    func testSkillScorerMaxIsExpert() {
        var ans = SkillQuiz.Answers()
        for q in SkillQuiz.Q.allCases { ans.values[q.rawValue] = q.options.count - 1 }
        let r = SkillScorer.score(ans)
        XCTAssertEqual(r.total, 110)
        XCTAssertEqual(r.level, .expert)
    }

    func testSkillScorerMinimumIsBeginner() {
        var ans = SkillQuiz.Answers()
        for q in SkillQuiz.Q.allCases { ans.values[q.rawValue] = 0 }
        let r = SkillScorer.score(ans)
        XCTAssertEqual(r.total, 3)        // bottom-turn floor (idx 0 = 3 pts)
        XCTAssertEqual(r.level, .beginner)
    }

    /// Verify every bucket boundary crosses where the spec says it should.
    func testSkillScorerBucketBoundaries() {
        // 25 → beginner / 26 → novice
        var r = SkillScorer.score(answers([.paddleEndurance: 2, .popUpConsistency: 3, .cutback: 1]))
        XCTAssertEqual(r.total, 25); XCTAssertEqual(r.level, .beginner)
        r = SkillScorer.score(answers([.paddleEndurance: 2, .popUpConsistency: 3, .biggestWave: 1, .yearsSurfing: 1]))
        XCTAssertEqual(r.total, 26); XCTAssertEqual(r.level, .novice)

        // 45 → novice / 46 → intermediate
        r = SkillScorer.score(answers([.bottomTurn: 2, .peakManeuver: 2, .paddleEndurance: 2, .cutback: 1]))
        XCTAssertEqual(r.total, 45); XCTAssertEqual(r.level, .novice)
        r = SkillScorer.score(answers([.bottomTurn: 2, .peakManeuver: 2, .paddleEndurance: 2, .biggestWave: 1, .yearsSurfing: 1]))
        XCTAssertEqual(r.total, 46); XCTAssertEqual(r.level, .intermediate)

        // 75 → intermediate / 76 → advanced
        r = SkillScorer.score(answers([.bottomTurn: 2, .peakManeuver: 2, .paddleEndurance: 2, .popUpConsistency: 3, .cutback: 2, .tubeRiding: 2, .waveReading: 1]))
        XCTAssertEqual(r.total, 75); XCTAssertEqual(r.level, .intermediate)
        r = SkillScorer.score(answers([.bottomTurn: 2, .peakManeuver: 2, .paddleEndurance: 2, .popUpConsistency: 3, .cutback: 2, .tubeRiding: 2, .biggestWave: 1, .yearsSurfing: 1]))
        XCTAssertEqual(r.total, 76); XCTAssertEqual(r.level, .advanced)

        // 95 → advanced / 96 → expert (start from the 110 max, then knock points off)
        r = SkillScorer.score(maxAnswers(overriding: [.peakManeuver: 0]))           // -15
        XCTAssertEqual(r.total, 95); XCTAssertEqual(r.level, .advanced)
        r = SkillScorer.score(maxAnswers(overriding: [.peakManeuver: 1, .waveReading: 1, .sessionFrequency: 2]))  // -8 -5 -1
        XCTAssertEqual(r.total, 96); XCTAssertEqual(r.level, .expert)
    }
}

// MARK: - Phase 1: Gemini-primary engine (safety layer, sizing, fallback, feedback)

final class GeminiRecommenderTests: XCTestCase {

    // MARK: fixtures

    private func spot(
        optimalMin: Double = 260, optimalMax: Double = 300,
        character: WaveCharacter = .performancePoint, tide: TidePreference = .allTides
    ) -> Spot {
        Spot(
            id: "rincon-cove", name: "Rincon",
            lat: 34.37, lon: -119.47, region: .sbSouth,
            ndbcBuoyId: "46053", tideStationId: "9411340",
            optimalSwellDirMinDeg: optimalMin, optimalSwellDirMaxDeg: optimalMax,
            favorableWindDirMinDeg: 0, favorableWindDirMaxDeg: 90,
            waveCharacter: character, tidePreference: tide, notes: "Cobblestone point."
        )
    }

    private func conditions(waveFt: Double = 3, period: Double = 11, swellDir: Double = 280) -> ConditionsSnapshot {
        ConditionsSnapshot(
            spotId: "rincon-cove", timestamp: Date(), fetchedAt: Date(),
            swellHeightM: waveFt / 3.28084, swellPeriodS: period, swellDirDeg: swellDir,
            waveHeightM: nil, wavePeriodS: nil, waveDirDeg: nil,
            windSpeedKt: 5, windDirDeg: 45, windGustKt: nil,
            tideHeightM: 3.0 / 3.28084, tideTrend: .rising,
            buoyWaveHeightM: nil, buoyDominantPeriodS: nil, buoyMeanDirDeg: nil
        )
    }

    private func profile(weightLb: Double = 170, skill: SkillLevel = .intermediate, heightIn: Double = 70) -> UserProfile {
        UserProfile(heightIn: heightIn, weightLb: weightLb, age: 30, gender: .preferNotToSay, skillLevel: skill)
    }

    private func decode(_ json: String) -> GeminiRecResponse {
        try! JSONDecoder().decode(GeminiRecResponse.self, from: json.data(using: .utf8)!)
    }

    // MARK: sizing — DimensionBuilder hits Gemini's EXACT volume

    func testSizing_HitsExactTargetVolume() {
        let s = DimensionBuilder().suggestForTargetVolume(
            type: .shortboard, skill: .intermediate, targetVolumeL: 32.0, userHeightIn: 70)
        XCTAssertEqual(s.volumeL, 32.0, accuracy: 1.5, "snapped dims should land on the target volume")
        XCTAssertGreaterThanOrEqual(s.widthIn, 18.25)
        XCTAssertLessThanOrEqual(s.thicknessIn, 3.5)
    }

    func testSizing_GrovelerHasHardFloorAndWidthClamp() {
        // A short surfer (5'6") used to get sub-5'2" grovelers (floor was height−6"). Now floored at
        // 62", and a too-short groveler can't rebalance to an unrealistic width.
        let b = DimensionBuilder()
        for preferredLength in [54.0, 58.0, 60.0] {   // Gemini pushing it stubby
            let s = b.suggestForTargetVolume(
                type: .groveler, skill: .intermediate, targetVolumeL: 33.0,
                userHeightIn: 66, preferredLengthIn: preferredLength)
            XCTAssertGreaterThanOrEqual(s.lengthIn, 62.0, "groveler floored at 5'2\"")
            XCTAssertLessThanOrEqual(s.widthIn, 22.0, "groveler width clamped")
            XCTAssertGreaterThanOrEqual(s.widthIn, 19.5)
        }
    }

    func testSizing_HonorsDimPreferences() {
        let s = DimensionBuilder().suggestForTargetVolume(
            type: .shortboard, skill: .intermediate, targetVolumeL: 30.0, userHeightIn: 72,
            preferredLengthIn: 72)
        XCTAssertEqual(s.lengthIn, 72, accuracy: 0.5, "preferred length (within clamp) honored")
        XCTAssertEqual(s.volumeL, 30.0, accuracy: 1.5, "volume still solved to target")
    }

    // MARK: safety layer — unknown type rejected (→ full fallback)

    @MainActor
    func testSafetyLayer_UnknownTypeThrows() {
        let r = decode(#"{"primaryType":"banana","targetVolumeLiters":30,"rationale":["x"]}"#)
        XCTAssertThrowsError(try GeminiRecommender().map(
            r, profile: profile(), spot: spot(), conditions: conditions(), quiver: []))
    }

    // MARK: safety layer — danger re-asserted + Gemini's volume honored (NOT clamped to baseline)

    @MainActor
    func testSafetyLayer_ReassertsDangerAndHonorsVolume() {
        // Beginner in overhead (6 ft in the optimal window); Gemini returned no advisory.
        let r = decode(#"{"primaryType":"funboard","targetVolumeLiters":45.0,"rationale":["lots of float"]}"#)
        let rec = try! GeminiRecommender().map(
            r, profile: profile(weightLb: 160, skill: .beginner),
            spot: spot(), conditions: conditions(waveFt: 6, period: 12), quiver: [])
        XCTAssertEqual(rec.advisory?.title, "Above Skill Level", "danger floor re-asserted")
        XCTAssertEqual(rec.targetVolume.midpointL, 45.0, accuracy: 0.001, "Gemini volume honored, not clamped")
        XCTAssertTrue(rec.isAIGenerated)
        XCTAssertEqual(rec.primaryType, .funboard)
    }

    @MainActor
    func testSafetyLayer_KeepsGeminiAdvisoryWhenNoDanger() {
        let r = decode(#"{"primaryType":"shortboard","targetVolumeLiters":31.0,"advisory":{"title":"Tiny","detail":"weak","severity":"informational"},"rationale":["a"]}"#)
        let rec = try! GeminiRecommender().map(
            r, profile: profile(), spot: spot(), conditions: conditions(waveFt: 2, period: 8), quiver: [])
        XCTAssertEqual(rec.advisory?.title, "Tiny")
        XCTAssertEqual(rec.advisory?.severity, .informational)
    }

    // MARK: safety layer — quiver pick resolves to a real owned board

    @MainActor
    func testSafetyLayer_ResolvesQuiverPick() {
        let board = Board(nickname: "Lil Fishy", type: .fish, lengthIn: 70, widthIn: 21, thicknessIn: 2.6)
        let r = decode("""
        {"primaryType":"fish","targetVolumeLiters":33.0,"quiverPickBoardId":"\(board.id.uuidString)","quiverPickReason":"it'll fly in this mush","rationale":["a"]}
        """)
        let rec = try! GeminiRecommender().map(
            r, profile: profile(), spot: spot(), conditions: conditions(), quiver: [board])
        XCTAssertEqual(rec.quiverMatches.first?.board.id, board.id)
        XCTAssertEqual(rec.quiverMatches.first?.rationale, "it'll fly in this mush")
    }

    // MARK: fallback — no key means the Gemini path is skipped entirely

    func testFallback_NotConfigured() async {
        let client = GeminiClient(apiKey: "")
        XCTAssertFalse(client.isConfigured)
        XCTAssertFalse(GeminiRecommender(client: client).isConfigured)
        do {
            _ = try await client.generateJSON(systemInstruction: "s", userPrompt: "u", responseSchema: [:])
            XCTFail("expected notConfigured throw")
        } catch let e as GeminiError {
            if case .notConfigured = e {} else { XCTFail("wrong error \(e)") }
        } catch { XCTFail("wrong error type \(error)") }
    }

    // MARK: advisory severity ↔ schema token round-trip

    func testAdvisorySeverityApiValueRoundTrip() {
        for s in [AdvisorySeverity.informational, .severe, .danger] {
            XCTAssertEqual(AdvisorySeverity(apiValue: s.apiValue), s)
        }
        XCTAssertEqual(AdvisorySeverity(apiValue: "bogus"), .informational)
    }

    // MARK: feedback — round-trip + capped "Surfer Preferences" summary

    func testFeedback_RoundTripAndSummary() {
        let snap = RecSnapshot(boardType: "shortboard", lengthIn: 72, widthIn: 19.25,
                               thicknessIn: 2.5, volumeL: 32, conditionsSummary: "3 ft @ 11s", wasAIGenerated: true)
        let fb = RecFeedback(spotId: "rincon-cove", ratingUp: false, comment: "felt corky", snapshot: snap)
        XCTAssertEqual(fb.decodedSnapshot?.boardType, "shortboard")
        XCTAssertTrue(fb.wasAIGenerated)
        let summary = RecFeedback.preferenceSummary(from: [fb])
        XCTAssertEqual(summary.count, 1)
        XCTAssertTrue(summary[0].contains("corky"))
        XCTAssertTrue(summary[0].contains("disliked"))
    }

    func testFeedback_SummaryCappedAtFive() {
        let rows = (0..<8).map { i -> RecFeedback in
            let snap = RecSnapshot(boardType: "fish", lengthIn: 68, widthIn: 21, thicknessIn: 2.6,
                                   volumeL: 35, conditionsSummary: "x", wasAIGenerated: true)
            return RecFeedback(spotId: "s", ratingUp: true, comment: "c\(i)", snapshot: snap,
                               createdAt: Date().addingTimeInterval(Double(i)))
        }
        let summary = RecFeedback.preferenceSummary(from: rows)
        XCTAssertEqual(summary.count, 5, "cap at 5 to avoid over-anchoring")
        XCTAssertTrue(summary[0].contains("c7"), "most recent first")
    }

    // MARK: prompt — includes authoritative spot metrics + quiver ids, no legacy baseline

    func testPrompt_IncludesSpotWindowAndQuiverId() {
        let board = Board(nickname: "Daily", type: .shortboard, lengthIn: 72, widthIn: 19, thicknessIn: 2.4)
        let prompt = GeminiRecommender.buildPrompt(
            profile: profile(), spot: spot(), conditions: conditions(), quiver: [board],
            preferences: ["User liked a Fish."])
        XCTAssertTrue(prompt.contains("Optimal swell window: 260°–300°"))
        XCTAssertTrue(prompt.contains(board.id.uuidString))
        XCTAssertTrue(prompt.contains("Surfer Preferences"))
    }
}

// MARK: - Phase 2 — wetsuit system

final class WetsuitSelectorTests: XCTestCase {

    private func profile(spring: Bool = false, t32: Bool = false,
                         t43: Bool = false, hood: Bool = false) -> UserProfile {
        let p = UserProfile(heightIn: 70, weightLb: 170, age: 30, gender: .preferNotToSay, skillLevel: .intermediate)
        p.hasSpringSuit = spring; p.has32 = t32; p.has43 = t43; p.hasHoodBooties = hood
        return p
    }

    private func spot() -> Spot {
        Spot(id: "rincon-cove", name: "Rincon", lat: 34.37, lon: -119.47, region: .sbSouth,
             ndbcBuoyId: nil, tideStationId: nil,
             optimalSwellDirMinDeg: 260, optimalSwellDirMaxDeg: 300,
             favorableWindDirMinDeg: 0, favorableWindDirMaxDeg: 90, notes: nil)
    }

    func testIdealSuitBands() {
        let s = WetsuitSelector()
        XCTAssertNil(s.idealSuit(waterTempF: 70))
        XCTAssertEqual(s.idealSuit(waterTempF: 64), .springSuit)
        XCTAssertEqual(s.idealSuit(waterTempF: 60), .threeTwo)
        XCTAssertEqual(s.idealSuit(waterTempF: 55), .fourThree)
        XCTAssertEqual(s.idealSuit(waterTempF: 49), .fourThreeHoodBooties)
    }

    func testColdWater_IdealAndPenalty_FullKit() {
        let r = WetsuitSelector().resolve(waterTempF: 50, profile: profile(t43: true, hood: true))
        XCTAssertEqual(r.ideal, .fourThreeHoodBooties)
        XCTAssertEqual(r.selected, .fourThreeHoodBooties)
        XCTAssertNil(r.gap)
        XCTAssertEqual(r.penaltyLb, 8, accuracy: 0.001)
    }

    func testOwnedGearGap_FlaggedWhenUnderRubbered() {
        // Needs a 4/3, owns only a 3/2 → wear the 3/2, flag the gap.
        let r = WetsuitSelector().resolve(waterTempF: 55, profile: profile(t32: true))
        XCTAssertEqual(r.ideal, .fourThree)
        XCTAssertEqual(r.selected, .threeTwo)
        XCTAssertNotNil(r.gap)
        XCTAssertEqual(r.penaltyLb, 3, accuracy: 0.001)
    }

    func testWarmWater_TrunksNoPenalty() {
        let r = WetsuitSelector().resolve(waterTempF: 72, profile: profile(t43: true))
        XCTAssertNil(r.ideal)
        XCTAssertNil(r.selected)
        XCTAssertEqual(r.penaltyLb, 0, accuracy: 0.001)
    }

    func testNoTemp_NoneResolution() {
        let r = WetsuitSelector().resolve(waterTempF: nil, profile: profile(t43: true))
        XCTAssertNil(r.selected)
        XCTAssertEqual(r.penaltyLb, 0, accuracy: 0.001)
    }

    func testPenaltyRaisesFallbackVolume() {
        let calc = VolumeCalculator()
        let base = calc.targetVolume(weightKg: 77, skill: .intermediate, age: 30,
                                     adjustedHeightFt: 3, periodS: 11)
        let withSuit = calc.targetVolume(weightKg: 77, skill: .intermediate, age: 30,
                                         adjustedHeightFt: 3, periodS: 11, wetWeightPenaltyLb: 8)
        XCTAssertGreaterThan(withSuit.midpointL, base.midpointL,
                             "wet-weight penalty should raise the fallback target volume")
    }

    func testPrompt_IncludesWetsuitContext() {
        var snap = ConditionsSnapshot.empty(spotId: "rincon-cove")
        snap.waterTempC = 10   // 50°F → 4/3 + hood/booties
        let p = profile(t43: true, hood: true)
        let w = WetsuitSelector().resolve(waterTempF: snap.waterTempF, profile: p)
        let prompt = GeminiRecommender.buildPrompt(
            profile: p, spot: spot(), conditions: snap, quiver: [], preferences: [], wetsuit: w)
        XCTAssertTrue(prompt.contains("Water temp"))
        XCTAssertTrue(prompt.contains("Wetsuit today"))
        XCTAssertTrue(prompt.contains("4/3 + hood & booties"))
    }
}
