import Foundation

struct VolumeRange: Equatable, Sendable {
    let lowL: Double
    let highL: Double
    var midpointL: Double { (lowL + highL) / 2 }

    func formatted() -> String {
        String(format: "%.1f–%.1f L", lowL, highL)
    }
}

// Not Sendable: holds a `Board` (a SwiftData `@Model`, a mutable reference type). Built and
// consumed on the MainActor, so no cross-actor sharing is needed.
struct QuiverMatch {
    let board: Board
    let score: Double
    let rationale: String
}

struct DimensionSuggestion: Sendable {
    let type: BoardType
    let lengthIn: Double
    let widthIn: Double
    let thicknessIn: Double
    let volumeL: Double

    var display: String {
        let lenFt = Int(lengthIn) / 12
        let lenInRem = lengthIn.truncatingRemainder(dividingBy: 12)
        let lenStr = "\(lenFt)'\(String(format: "%.1f", lenInRem))\""
        return String(format: "%@  %@ × %.2f × %.2f  ≈ %.1f L",
                      type.displayName, lenStr, widthIn, thicknessIn, volumeL)
    }
}

// Not Sendable: transitively holds a `Board` via `quiverMatches`. MainActor-only, like `QuiverMatch`.
struct Recommendation {
    let targetVolume: VolumeRange
    let primaryType: BoardType
    let alternateTypes: [BoardType]
    let quiverMatches: [QuiverMatch]
    let dimensionSuggestion: DimensionSuggestion
    let advisory: Advisory?
    let rationale: [String]
    /// True when Gemini produced this rec; false for the rule-engine fallback. Drives the
    /// "AI vs. rules" UI label and is stored alongside feedback.
    var isAIGenerated: Bool = false
}

/// Physics gates that resolve the raw forecast into the numbers the engine actually reasons about.
enum Gates {
    /// Island-shadowing: reduce the forecast height based on how far the swell direction sits
    /// outside the spot's optimal window. Returns the adjusted height and whether it was *blocked*.
    static func shadow(forecastFt: Double, swellDirDeg: Double?, spot: Spot) -> (adjusted: Double, blocked: Bool) {
        guard let dir = swellDirDeg else { return (forecastFt, false) }
        let outside = spot.degreesOutsideWindow(dir)
        if outside == 0 { return (forecastFt, false) }          // in window
        if outside <= 20 { return (forecastFt * 0.5, false) }   // marginal — halve
        return (min(forecastFt, 1.0), true)                     // blocked — capped flat
    }
}

struct Recommender: Sendable {
    let volumeCalculator: VolumeCalculator
    let boardTypeSelector: BoardTypeSelector
    let quiverMatcher: QuiverMatcher
    let dimensionBuilder: DimensionBuilder
    let wetsuitSelector: WetsuitSelector

    init(
        volumeCalculator: VolumeCalculator = VolumeCalculator(),
        boardTypeSelector: BoardTypeSelector = BoardTypeSelector(),
        quiverMatcher: QuiverMatcher = QuiverMatcher(),
        dimensionBuilder: DimensionBuilder = DimensionBuilder(),
        wetsuitSelector: WetsuitSelector = WetsuitSelector()
    ) {
        self.volumeCalculator = volumeCalculator
        self.boardTypeSelector = boardTypeSelector
        self.quiverMatcher = quiverMatcher
        self.dimensionBuilder = dimensionBuilder
        self.wetsuitSelector = wetsuitSelector
    }

    func recommend(
        profile: UserProfile,
        spot: Spot,
        conditions: ConditionsSnapshot,
        quiver: [Board]
    ) -> Recommendation {
        let forecastFt = conditions.primarySwellHeightFt ?? 2.0
        let periodS = conditions.primarySwellPeriodS ?? 10.0
        let swellDir = conditions.primarySwellDirDeg

        var advisories: [Advisory] = []
        var rationale: [String] = []

        // Gate 1 — island shadowing.
        let (adjustedHeightFt, blocked) = Gates.shadow(forecastFt: forecastFt, swellDirDeg: swellDir, spot: spot)
        if blocked {
            advisories.append(AdvisoryFactory.swellShadowed())
            rationale.append(String(format: "Swell is shadowed by the islands — sizing off ~%.1f ft, not the %.1f ft raw forecast.",
                                    adjustedHeightFt, forecastFt))
        }

        // Gate 2 — tide swamping.
        let tideSwamped = (spot.tidePreference == .lowToMid) && ((conditions.tideHeightFt ?? 0) > 4.5)
        if tideSwamped { advisories.append(AdvisoryFactory.tideSwamped()) }

        // Danger — over-matched for skill.
        if isOverMatched(skill: profile.skillLevel, heightFt: adjustedHeightFt) {
            advisories.append(AdvisoryFactory.aboveSkillLevel())
        }

        // Wind — blown out.
        let blownOut = BlownOutAdvisor().evaluate(conditions: conditions, spot: spot)
        if let blownOut { advisories.append(blownOut) }
        let isBlownOut = blownOut != nil

        // Wetsuit — wet-weight penalty for the suit the surfer will actually wear (Phase 2).
        let wetsuit = wetsuitSelector.resolve(waterTempF: conditions.waterTempF, profile: profile)
        if let suit = wetsuit.selected {
            rationale.append("Sized for a \(suit.displayName) (water ~\(Int((conditions.waterTempF ?? 0).rounded()))°F).")
        }

        // Volume — thread the shadow-adjusted height + stacked bumps + wet-weight penalty.
        var extra = 1.0
        if tideSwamped { extra *= 1.05 }
        if spot.waveCharacter == .softAndSlow { extra *= 1.05 }
        if isBlownOut { extra *= 1.07 }     // forgiving float in chop
        let volume = volumeCalculator.targetVolume(
            weightKg: profile.weightKg,
            skill: profile.skillLevel,
            age: profile.age,
            adjustedHeightFt: adjustedHeightFt,
            periodS: periodS,
            extraMultiplier: extra,
            wetWeightPenaltyLb: wetsuit.penaltyLb
        )

        // Board type — matrix → tide downgrade → wave-character override.
        var typeChoice = boardTypeSelector.choose(
            adjustedHeightFt: adjustedHeightFt,
            periodS: periodS,
            isBlownOut: isBlownOut,
            skill: profile.skillLevel
        )
        if tideSwamped && !isBlownOut {
            typeChoice = downgrade(typeChoice, note: "High tide is swamping the spot — going more forgiving.")
        }
        if !isBlownOut {
            typeChoice = applyWaveCharacter(spot.waveCharacter, to: typeChoice, heightFt: adjustedHeightFt)
        }

        // Quiver + dimensions.
        let matches = quiverMatcher.match(
            quiver: quiver,
            type: typeChoice.primary,
            adjacent: typeChoice.alternates,
            targetVolume: volume
        )
        let dimSuggestion = dimensionBuilder.suggest(
            type: typeChoice.primary,
            skill: profile.skillLevel,
            targetVolume: volume,
            userHeightIn: profile.heightIn,
            userWeightLb: profile.weightLb
        )

        rationale.insert(contentsOf: typeChoice.rationale, at: 0)
        rationale.append("Target volume \(volume.formatted()) (\(profile.skillLevel.displayName), \(Int(profile.weightLb)) lb).")

        return Recommendation(
            targetVolume: volume,
            primaryType: typeChoice.primary,
            alternateTypes: typeChoice.alternates,
            quiverMatches: matches,
            dimensionSuggestion: dimSuggestion,
            advisory: AdvisoryFactory.resolve(advisories),
            rationale: rationale
        )
    }

    // MARK: - Gates / overrides

    private func isOverMatched(skill: SkillLevel, heightFt: Double) -> Bool {
        switch skill {
        case .beginner, .novice: return heightFt > 5
        case .intermediate: return heightFt > 8
        case .advanced, .expert: return false
        }
    }

    /// One step toward float — used by the tide-swamp gate.
    private func downgrade(_ choice: BoardTypeChoice, note: String) -> BoardTypeChoice {
        let newPrimary = choice.primary.downgradeTier()
        guard newPrimary != choice.primary else { return choice }
        var reasons = choice.rationale
        reasons.append(note)
        return BoardTypeChoice(primary: newPrimary, alternates: makeAlternates(newPrimary, choice.primary), rationale: reasons)
    }

    /// Spot wave-character override (Model 3).
    private func applyWaveCharacter(_ character: WaveCharacter, to choice: BoardTypeChoice, heightFt: Double) -> BoardTypeChoice {
        var reasons = choice.rationale
        switch character {
        case .performancePoint:
            return choice

        case .softAndSlow:
            // No HPSBs (or other performance blades) on soft waves — step one tier toward float.
            guard isPerformanceish(choice.primary) else { return choice }
            let p = choice.primary.downgradeTier()
            reasons.append("Soft, slow wave — stepping to a more forgiving \(p.displayName).")
            return BoardTypeChoice(primary: p, alternates: makeAlternates(p, choice.primary), rationale: reasons)

        case .heavyHollow:
            let p = choice.primary.upgradeTier()
            if choice.primary == .groveler || choice.primary == .fish {
                reasons.append("Heavy wave — flat rockers will dig the nose; bumping to \(p.displayName).")
            } else if p == choice.primary {
                reasons.append("Heavy, hollow wave — holding the performance pick.")
            } else {
                reasons.append("Heavy, hollow wave — stepping up to \(p.displayName).")
            }
            // Solid + heavy: offer a step-up as an alternate.
            let extra: BoardType = heightFt >= 5 ? .stepUp : choice.primary
            return BoardTypeChoice(primary: p, alternates: makeAlternates(p, extra), rationale: reasons)
        }
    }

    private func isPerformanceish(_ type: BoardType) -> Bool {
        switch type {
        case .hpsb, .shortboard, .allRounder, .stepUp, .gun: true
        default: false
        }
    }

    /// Build up to 3 alternates: the preferred picks first (if distinct), then the primary's neighbors.
    private func makeAlternates(_ primary: BoardType, _ preferred: BoardType...) -> [BoardType] {
        var out: [BoardType] = []
        for p in preferred where p != primary && !out.contains(p) { out.append(p) }
        for a in primary.adjacent where a != primary && !out.contains(a) { out.append(a) }
        return Array(out.prefix(3))
    }
}

// MARK: - Gemini-primary recommender (Phase 1)
//
// Appended here (rather than a new file) because xcodegen isn't installed — a brand-new `.swift`
// wouldn't be in the generated project. `GeminiRecommender` makes Gemini the primary brain: it owns
// the board type, the exact target volume, the aesthetic shape intent, and the quiver pick. Our local
// `DimensionBuilder` turns Gemini's volume into a physically buildable board, and a thin safety layer
// re-asserts danger advisories. On ANY failure the caller falls back to the rule `Recommender`.

/// The structured-output contract Gemini must return for a single recommendation.
struct GeminiRecResponse: Decodable, Sendable {
    let primaryType: String
    let alternateTypes: [String]?
    let targetVolumeLiters: Double
    let dimPreferences: DimPrefs?
    let quiverPickBoardId: String?
    let quiverPickReason: String?
    let advisory: AdvisoryPayload?
    let rationale: [String]?

    struct DimPrefs: Decodable, Sendable {
        let lengthIn: Double?
        let widthIn: Double?
        let thicknessIn: Double?
    }

    struct AdvisoryPayload: Decodable, Sendable {
        let title: String
        let detail: String
        let severity: String
    }
}

/// The batched 7-day forecast contract — one entry per day, keyed by `dayIndex` into the days we sent.
struct GeminiForecastResponse: Decodable, Sendable {
    let days: [Day]
    struct Day: Decodable, Sendable {
        let dayIndex: Int
        let primaryType: String?
        let targetVolumeLiters: Double
    }
}

struct GeminiRecommender: Sendable {
    let client: GeminiClient
    let dimensionBuilder: DimensionBuilder
    let blownOutAdvisor: BlownOutAdvisor

    init(
        client: GeminiClient = GeminiClient(),
        dimensionBuilder: DimensionBuilder = DimensionBuilder(),
        blownOutAdvisor: BlownOutAdvisor = BlownOutAdvisor()
    ) {
        self.client = client
        self.dimensionBuilder = dimensionBuilder
        self.blownOutAdvisor = blownOutAdvisor
    }

    var isConfigured: Bool { client.isConfigured }

    /// Synthesize a tight display band (±1.5 L) around Gemini's single liter target.
    static func displayRange(forTarget liters: Double) -> VolumeRange {
        VolumeRange(lowL: liters - 1.5, highL: liters + 1.5)
    }

    // MARK: Live recommendation

    /// Live recommendation. Throws on no key / network / parse / invalid type so the caller falls back.
    /// `@MainActor` because it reads `Board` (a SwiftData `@Model`) when resolving the quiver pick.
    @MainActor
    func recommend(
        profile: UserProfile,
        spot: Spot,
        conditions: ConditionsSnapshot,
        quiver: [Board],
        preferences: [String],
        wetsuit: WetsuitResolution = .none
    ) async throws -> Recommendation {
        let system = Self.systemInstruction
        let prompt = Self.buildPrompt(
            profile: profile, spot: spot, conditions: conditions, quiver: quiver,
            preferences: preferences, wetsuit: wetsuit
        )
        let data = try await client.generateJSON(
            systemInstruction: system,
            userPrompt: prompt,
            responseSchema: Self.recommendationSchema
        )
        let decoded: GeminiRecResponse
        do {
            decoded = try JSONDecoder().decode(GeminiRecResponse.self, from: data)
        } catch {
            let preview = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw GeminiError.decoding("\(error)  payload=\(preview)")
        }
        return try map(decoded, profile: profile, spot: spot, conditions: conditions, quiver: quiver)
    }

    /// Maps a decoded response onto our `Recommendation` and runs the safety layer.
    /// Internal (not private) so the safety layer can be unit-tested from canned JSON without network.
    @MainActor
    func map(
        _ r: GeminiRecResponse,
        profile: UserProfile,
        spot: Spot,
        conditions: ConditionsSnapshot,
        quiver: [Board]
    ) throws -> Recommendation {
        // Safety: the primary type MUST decode to a real BoardType, else reject the whole response.
        guard let primary = BoardType(rawValue: r.primaryType) else {
            throw GeminiError.decoding("unknown primaryType '\(r.primaryType)'")
        }
        let alternates = (r.alternateTypes ?? []).compactMap { BoardType(rawValue: $0) }.filter { $0 != primary }

        // Honor Gemini's EXACT volume — DimensionBuilder solves buildable dims for it (no clamp to baseline).
        let dims = dimensionBuilder.suggestForTargetVolume(
            type: primary,
            skill: profile.skillLevel,
            targetVolumeL: r.targetVolumeLiters,
            userHeightIn: profile.heightIn,
            preferredLengthIn: r.dimPreferences?.lengthIn,
            preferredWidthIn: r.dimPreferences?.widthIn,
            preferredThicknessIn: r.dimPreferences?.thicknessIn
        )

        // Quiver pick → resolve the owned board Gemini referenced by id.
        var matches: [QuiverMatch] = []
        if let idStr = r.quiverPickBoardId, let uuid = UUID(uuidString: idStr),
           let board = quiver.first(where: { $0.id == uuid }) {
            let reason = r.quiverPickReason ?? "Best match in your quiver for today."
            matches = [QuiverMatch(board: board, score: 0, rationale: reason)]
        }

        // Advisory + safety re-assert: rules always run; the highest-severity advisory wins the banner.
        var candidates: [Advisory] = []
        if let a = r.advisory {
            candidates.append(Advisory(title: a.title, detail: a.detail,
                                       severity: AdvisorySeverity(apiValue: a.severity)))
        }
        let forecastFt = conditions.primarySwellHeightFt ?? 2.0
        let (adjustedHeightFt, _) = Gates.shadow(forecastFt: forecastFt, swellDirDeg: conditions.primarySwellDirDeg, spot: spot)
        if Self.isOverMatched(skill: profile.skillLevel, heightFt: adjustedHeightFt) {
            candidates.append(AdvisoryFactory.aboveSkillLevel())
        }
        if let blownOut = blownOutAdvisor.evaluate(conditions: conditions, spot: spot) {
            candidates.append(blownOut)
        }

        return Recommendation(
            targetVolume: Self.displayRange(forTarget: r.targetVolumeLiters),
            primaryType: primary,
            alternateTypes: alternates,
            quiverMatches: matches,
            dimensionSuggestion: dims,
            advisory: AdvisoryFactory.resolve(candidates),
            rationale: r.rationale ?? [],
            isAIGenerated: true
        )
    }

    // MARK: Batched 7-day forecast

    /// One batched call: send a representative snapshot per day, get back one volume target per day.
    /// `dailyConditions` must be ordered; `dayIndex` in the response refers to that order.
    @MainActor
    func forecast(
        profile: UserProfile,
        spot: Spot,
        dailyConditions: [(date: Date, snapshot: ConditionsSnapshot)],
        preferences: [String]
    ) async throws -> [ForecastVolume.DailyMin] {
        guard !dailyConditions.isEmpty else { return [] }
        let prompt = Self.buildForecastPrompt(
            profile: profile, spot: spot, dailyConditions: dailyConditions, preferences: preferences
        )
        let data = try await client.generateJSON(
            systemInstruction: Self.systemInstruction,
            userPrompt: prompt,
            responseSchema: Self.forecastSchema
        )
        let decoded = try JSONDecoder().decode(GeminiForecastResponse.self, from: data)
        let byIndex = Dictionary(decoded.days.map { ($0.dayIndex, $0) }, uniquingKeysWith: { a, _ in a })

        return dailyConditions.enumerated().compactMap { idx, day in
            guard let pick = byIndex[idx] else { return nil }
            return ForecastVolume.DailyMin(
                date: day.date,
                swellFt: day.snapshot.primarySwellHeightFt,
                periodS: day.snapshot.primarySwellPeriodS,
                range: Self.displayRange(forTarget: pick.targetVolumeLiters)
            )
        }
    }

    // MARK: Safety helpers

    /// Same danger floor the rule engine uses — re-asserted regardless of what Gemini returned.
    static func isOverMatched(skill: SkillLevel, heightFt: Double) -> Bool {
        switch skill {
        case .beginner, .novice: return heightFt > 5
        case .intermediate: return heightFt > 8
        case .advanced, .expert: return false
        }
    }

    // MARK: Prompt building

    static let systemInstruction = """
    You are an expert surfboard shaper and coach sizing a board for one surfer at one specific spot \
    under live conditions. Reason holistically over the surfer's body, age, skill, the spot's character, \
    and the live swell/wind/tide — the way a seasoned shaper would when handing someone a board.

    Use your geographic knowledge of the Ventura and Santa Barbara coastlines for environmental \
    context, but strictly adhere to the specific swell windows, optimal wind directions, and wave \
    character metrics provided in the spots.json input.

    Board type vocabulary (use these exact tokens for `primaryType`/`alternateTypes`):
    - hpsb: high-performance shortboard, a pro blade — only for clean, powerful waves and skilled surfers.
    - shortboard: daily-driver shortboard, moderate rocker.
    - allRounder: forgiving hybrid shortboard.
    - groveler: low, wide, flat shortboard for small mushy waves.
    - fish: fast, wide, flat twin/quad for small-to-medium waves.
    - midLength: 6'8"–8'6" single/2+1, glide and paddle power.
    - funboard: forgiving mid-volume board for learners and small days.
    - longboard: 8'6"+ plank, maximum float and glide.
    - stepUp: a shortboard with more length/foil for bigger, heavier waves.
    - gun: a long, narrow board for large, powerful surf.

    Units: lengths/widths/thicknesses in inches, volume in liters, swell height in feet, period in \
    seconds, wind in knots, directions in compass degrees. Volume should be appropriate for the \
    surfer's weight and skill (beginners float much more; experts ride much less).

    If a wetsuit is given, factor it in: thicker rubber adds buoyancy and paddling weight and reduces \
    shoulder mobility, so it generally nudges the target volume up and favors slightly more forgiving \
    shapes; an under-rubbered surfer (a flagged gap) will fatigue faster and wants easier waves to catch.

    Output ONLY the JSON object matching the provided schema. `targetVolumeLiters` is the single exact \
    volume you want the surfer on today; `dimPreferences` is OPTIONAL aesthetic intent (the app solves \
    the precise dimensions to your volume). If you reference an owned board, set `quiverPickBoardId` to \
    that board's exact id from the quiver list.
    """

    static func buildPrompt(
        profile: UserProfile,
        spot: Spot,
        conditions: ConditionsSnapshot,
        quiver: [Board],
        preferences: [String],
        wetsuit: WetsuitResolution = .none
    ) -> String {
        var lines: [String] = []

        lines.append("## Surfer")
        lines.append("- Height: \(heightString(profile.heightIn)) (\(Int(profile.heightIn)) in)")
        lines.append("- Weight: \(Int(profile.weightLb)) lb")
        lines.append("- Age: \(profile.age)")
        lines.append("- Skill: \(profile.skillLevel.displayName)")
        if let temp = conditions.waterTempF {
            lines.append(String(format: "- Water temp: %.0f°F", temp))
        }
        if let suit = wetsuit.selected {
            lines.append("- Wetsuit today: \(suit.displayName) — \(suit.performanceNote) (adds ~\(Int(wetsuit.penaltyLb)) lb of wet weight; factor the extra float and reduced mobility into volume and type.)")
        } else if wetsuit.ideal == nil && conditions.waterTempF != nil {
            lines.append("- Wetsuit today: trunks / boardshorts (warm water, no rubber penalty).")
        }
        if let gap = wetsuit.gap {
            lines.append("- Wetsuit gap: \(gap)")
        }

        lines.append("\n## Spot (authoritative — obey these metrics)")
        lines.append("- Name: \(spot.name) (\(spot.region.displayName))")
        lines.append("- Wave character: \(spot.waveCharacter.rawValue)")
        lines.append("- Tide preference: \(spot.tidePreference.rawValue)")
        lines.append("- Optimal swell window: \(Int(spot.optimalSwellDirMinDeg))°–\(Int(spot.optimalSwellDirMaxDeg))°")
        lines.append("- Favorable wind window: \(Int(spot.favorableWindDirMinDeg))°–\(Int(spot.favorableWindDirMaxDeg))°")
        if let notes = spot.notes { lines.append("- Notes: \(notes)") }

        lines.append("\n## Live conditions")
        lines.append("- " + conditionsLine(conditions, spot: spot))

        lines.append("\n## Quiver (owned boards — reference one by its id if it fits)")
        if quiver.isEmpty {
            lines.append("- (empty)")
        } else {
            for b in quiver {
                let name = b.nickname ?? b.type.displayName
                lines.append(String(
                    format: "- id=%@ | %@ | %@ | %@ %.2f × %.2f | %.1f L",
                    b.id.uuidString, name, b.type.rawValue, b.lengthDisplay, b.widthIn, b.thicknessIn, b.effectiveVolumeL))
            }
        }

        if !preferences.isEmpty {
            lines.append("\n## Surfer Preferences (recent feedback — soft subjective signal, NOT hard rules)")
            for p in preferences { lines.append("- \(p)") }
        }

        lines.append("\nRecommend the single best board for this surfer at this spot right now.")
        return lines.joined(separator: "\n")
    }

    static func buildForecastPrompt(
        profile: UserProfile,
        spot: Spot,
        dailyConditions: [(date: Date, snapshot: ConditionsSnapshot)],
        preferences: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("## Surfer")
        lines.append("- \(heightString(profile.heightIn)), \(Int(profile.weightLb)) lb, age \(profile.age), \(profile.skillLevel.displayName)")

        lines.append("\n## Spot (authoritative)")
        lines.append("- \(spot.name) — wave: \(spot.waveCharacter.rawValue), tide pref: \(spot.tidePreference.rawValue), swell window \(Int(spot.optimalSwellDirMinDeg))°–\(Int(spot.optimalSwellDirMaxDeg))°, wind window \(Int(spot.favorableWindDirMinDeg))°–\(Int(spot.favorableWindDirMaxDeg))°")

        if !preferences.isEmpty {
            lines.append("\n## Surfer Preferences (soft signal)")
            for p in preferences { lines.append("- \(p)") }
        }

        lines.append("\n## Daily conditions (one representative session per day)")
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        for (i, day) in dailyConditions.enumerated() {
            lines.append("- dayIndex=\(i) (\(df.string(from: day.date))): " + conditionsLine(day.snapshot, spot: spot))
        }

        lines.append("\nFor EACH dayIndex return one entry with the exact target volume (liters) and primary board type for that day's conditions. Return all \(dailyConditions.count) days.")
        return lines.joined(separator: "\n")
    }

    private static func conditionsLine(_ c: ConditionsSnapshot, spot: Spot) -> String {
        let h = c.primarySwellHeightFt.map { String(format: "%.1f ft", $0) } ?? "—"
        let p = c.primarySwellPeriodS.map { String(format: "%.0f s", $0) } ?? "—"
        let dirStr: String
        if let d = c.primarySwellDirDeg {
            let outside = spot.degreesOutsideWindow(d)
            let shadow = outside > 20 ? " — SHADOWED (>\(Int(outside))° outside window, energy blocked)"
                       : outside > 0 ? " — \(Int(outside))° outside optimal window"
                       : " — in optimal window"
            dirStr = "\(Units.compassPoint(degrees: d)) (\(Int(d))°)\(shadow)"
        } else {
            dirStr = "—"
        }
        let wind = c.windSpeedKt.map { String(format: "%.0f kt", $0) } ?? "—"
        let windDir = c.windDirDeg.map { Units.compassPoint(degrees: $0) } ?? "—"
        let tide = c.tideHeightFt.map { String(format: "%.1f ft", $0) } ?? "—"
        let trend = c.tideTrend.map { " (\($0.rawValue))" } ?? ""
        return "Swell \(h) @ \(p) from \(dirStr); Wind \(windDir) \(wind); Tide \(tide)\(trend)"
    }

    private static func heightString(_ heightIn: Double) -> String {
        let ft = Int(heightIn) / 12
        let inch = Int(heightIn) % 12
        return "\(ft)'\(inch)\""
    }

    // MARK: Response schemas (OpenAPI subset for Gemini structured output)

    private static var boardTypeEnum: [String] { BoardType.allCases.map(\.rawValue) }

    static var recommendationSchema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "primaryType": ["type": "STRING", "enum": boardTypeEnum],
                "alternateTypes": ["type": "ARRAY", "items": ["type": "STRING", "enum": boardTypeEnum]],
                "targetVolumeLiters": ["type": "NUMBER"],
                "dimPreferences": [
                    "type": "OBJECT",
                    "nullable": true,
                    "properties": [
                        "lengthIn": ["type": "NUMBER", "nullable": true],
                        "widthIn": ["type": "NUMBER", "nullable": true],
                        "thicknessIn": ["type": "NUMBER", "nullable": true]
                    ]
                ],
                "quiverPickBoardId": ["type": "STRING", "nullable": true],
                "quiverPickReason": ["type": "STRING", "nullable": true],
                "advisory": [
                    "type": "OBJECT",
                    "nullable": true,
                    "properties": [
                        "title": ["type": "STRING"],
                        "detail": ["type": "STRING"],
                        "severity": ["type": "STRING", "enum": ["informational", "severe", "danger"]]
                    ]
                ],
                "rationale": ["type": "ARRAY", "items": ["type": "STRING"]]
            ],
            "required": ["primaryType", "targetVolumeLiters", "rationale"]
        ]
    }

    static var forecastSchema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "days": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "dayIndex": ["type": "INTEGER"],
                            "primaryType": ["type": "STRING", "enum": boardTypeEnum, "nullable": true],
                            "targetVolumeLiters": ["type": "NUMBER"]
                        ],
                        "required": ["dayIndex", "targetVolumeLiters"]
                    ]
                ]
            ],
            "required": ["days"]
        ]
    }
}
