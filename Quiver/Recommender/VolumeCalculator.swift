import Foundation
import Vision
import CoreImage

struct VolumeCalculator: Sendable {

    /// Core target-volume calculation. `adjustedHeightFt` is the shadow-adjusted wave height
    /// (post island-shadowing). `extraMultiplier` carries tide-swamp / soft-wave / blown-out bumps.
    /// `V = weightKg × M_skill × M_cond × M_age × extra`.
    func targetVolume(
        weightKg: Double,
        skill: SkillLevel,
        age: Int,
        adjustedHeightFt: Double,
        periodS: Double,
        extraMultiplier: Double = 1.0,
        wetWeightPenaltyLb: Double = 0
    ) -> VolumeRange {
        let range = skill.multiplierRange
        let cond = conditionsAdjustment(heightFt: adjustedHeightFt, periodS: periodS)
        let ageAdj = ageAdjustment(age: age)
        // Wet rubber adds effective body weight → more float needed (Phase 2). 0 = no suit / no temp.
        let effectiveKg = weightKg + wetWeightPenaltyLb * 0.45359237
        let low = effectiveKg * range.lowerBound * cond.low * ageAdj * extraMultiplier
        let high = effectiveKg * range.upperBound * cond.high * ageAdj * extraMultiplier
        return VolumeRange(lowL: low, highL: high)
    }

    /// Convenience from a raw snapshot (no spot-shadowing applied). Used by `ForecastVolume`
    /// and standalone sizing; a non-nil advisory adds a forgiving-float bump.
    func targetVolume(
        weightKg: Double,
        skill: SkillLevel,
        age: Int,
        conditions: ConditionsSnapshot,
        advisory: Advisory?
    ) -> VolumeRange {
        targetVolume(
            weightKg: weightKg,
            skill: skill,
            age: age,
            adjustedHeightFt: conditions.primarySwellHeightFt ?? 3.0,
            periodS: conditions.primarySwellPeriodS ?? 11.0,
            extraMultiplier: advisory != nil ? 1.07 : 1.0
        )
    }

    func targetVolume(profile: UserProfile, conditions: ConditionsSnapshot, advisory: Advisory?) -> VolumeRange {
        targetVolume(
            weightKg: profile.weightKg, skill: profile.skillLevel, age: profile.age,
            conditions: conditions, advisory: advisory
        )
    }

    /// Scales the multiplier off the shadow-adjusted height (AND logic per spec):
    /// small/weak gets more float, solid/powerful gets less. Returns (low, high) to widen the range.
    func conditionsAdjustment(heightFt: Double, periodS: Double) -> (low: Double, high: Double) {
        if heightFt < 3 && periodS < 9 {
            return (1.05, 1.10)   // small / weak — extra float to catch them
        }
        if heightFt > 5 && periodS > 12 {
            return (0.92, 0.97)   // solid / powerful — less float, more control
        }
        return (1.0, 1.0)         // average
    }

    /// Banded age adjustment — paddle power declines per decade over 40.
    func ageAdjustment(age: Int) -> Double {
        switch age {
        case ..<40: 1.00
        case 40...49: 1.04
        case 50...59: 1.08
        default: 1.12
        }
    }
}

// MARK: - Phase 2 — Dynamic wetsuit system

/// The resolved wetsuit picture for a session: the temp-ideal suit, what the surfer will actually
/// wear given what they own, any owned-gear gap, and the wet-weight penalty for the worn suit.
struct WetsuitResolution: Sendable {
    let ideal: Wetsuit?      // what the water temp calls for (nil = trunks)
    let selected: Wetsuit?   // closest owned suit they'll actually wear (nil = trunks / owns nothing)
    let gap: String?         // owned-gear gap note, if under-rubbered
    let penaltyLb: Double    // wet-weight penalty for `selected`

    static let none = WetsuitResolution(ideal: nil, selected: nil, gap: nil, penaltyLb: 0)
}

/// Infers the ideal suit from sea-surface temp, matches it against owned rubber, and computes the
/// wet-weight penalty. Pure / `Sendable`. Temp bands & penalty ladder are first-pass estimates.
struct WetsuitSelector: Sendable {

    /// The suit the water temp calls for. `nil` = warm enough for trunks. Bands are monotonic:
    /// ≥68 trunks · ≥62 spring · ≥58 3/2 · ≥52 4/3 · <52 4/3 + hood/booties.
    func idealSuit(waterTempF: Double) -> Wetsuit? {
        switch waterTempF {
        case 68...: return nil
        case 62..<68: return .springSuit
        case 58..<62: return .threeTwo
        case 52..<58: return .fourThree
        default: return .fourThreeHoodBooties
        }
    }

    /// Standalone suits the surfer owns. The 4/3+hood/booties tier needs both a 4/3 and hood/booties.
    func ownedSuits(from profile: UserProfile) -> [Wetsuit] {
        var owned: [Wetsuit] = []
        if profile.hasSpringSuit { owned.append(.springSuit) }
        if profile.has32 { owned.append(.threeTwo) }
        if profile.has43 { owned.append(.fourThree) }
        if profile.has43 && profile.hasHoodBooties { owned.append(.fourThreeHoodBooties) }
        return owned
    }

    /// Full resolution from temp + profile. No temp → `.none` (penalty 0, identical to pre-Phase-2).
    func resolve(waterTempF: Double?, profile: UserProfile) -> WetsuitResolution {
        guard let tempF = waterTempF else { return .none }
        let ideal = idealSuit(waterTempF: tempF)
        guard let ideal else {
            // Warm — trunks. No penalty, no gap.
            return WetsuitResolution(ideal: nil, selected: nil, gap: nil, penaltyLb: 0)
        }
        let owned = ownedSuits(from: profile)
        guard !owned.isEmpty else {
            return WetsuitResolution(
                ideal: ideal, selected: nil,
                gap: "Water calls for a \(ideal.displayName), but no wetsuit is in your kit — expect to bail early.",
                penaltyLb: 0)
        }
        // Wear the owned suit closest in warmth to the ideal; tie-break toward the warmer one.
        let selected = owned.min { a, b in
            let da = abs(a.warmthRank - ideal.warmthRank)
            let db = abs(b.warmthRank - ideal.warmthRank)
            return da != db ? da < db : a.warmthRank > b.warmthRank
        }!
        let gap = selected.warmthRank < ideal.warmthRank
            ? "Water calls for a \(ideal.displayName) but you'll be in a \(selected.displayName) — expect cold fatigue."
            : nil
        return WetsuitResolution(ideal: ideal, selected: selected, gap: gap, penaltyLb: selected.wetWeightPenaltyLb)
    }
}
