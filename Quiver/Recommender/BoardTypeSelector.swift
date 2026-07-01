import Foundation

struct BoardTypeChoice: Sendable {
    let primary: BoardType
    let alternates: [BoardType]
    let rationale: [String]
}

struct BoardTypeSelector: Sendable {

    /// Baseline board-type matrix. Keyed on shadow-adjusted height, period, blown-out state, skill.
    /// Height-primary with period as a soft/clean modifier; first match wins, largest band first.
    /// Tide downgrade and wave-character overrides are applied afterward by the `Recommender`.
    func choose(
        adjustedHeightFt h: Double,
        periodS p: Double,
        isBlownOut: Bool,
        skill: SkillLevel
    ) -> BoardTypeChoice {
        var reasons: [String] = []
        reasons.append(String(format: "Resolved %.1f ft @ %.0fs.", h, p))

        if isBlownOut {
            reasons.append("Onshore / blown out — picking a forgiving board.")
            return BoardTypeChoice(primary: .midLength, alternates: [.funboard, .longboard], rationale: reasons)
        }

        let beginnerish = (skill == .beginner || skill == .novice)
        let advPlus = (skill == .advanced || skill == .expert)
        let cleanPowerful = p >= 12

        switch h {
        case ..<2:
            reasons.append("Tiny surf — longboard / mid-length.")
            return BoardTypeChoice(primary: .longboard, alternates: [.midLength, .funboard], rationale: reasons)

        case 2..<3:
            if beginnerish {
                reasons.append("Small surf — easy paddle board for your level.")
                return BoardTypeChoice(primary: .longboard, alternates: [.midLength], rationale: reasons)
            }
            reasons.append("Small, short-period — groveler / fish / all-rounder.")
            return BoardTypeChoice(primary: .groveler, alternates: [.fish, .allRounder], rationale: reasons)

        case 3..<6:
            // 3–6 ft window: skill + period (soft vs clean) pick the performance board.
            if beginnerish {
                reasons.append("Chest-to-head high — forgiving board for your level.")
                return BoardTypeChoice(primary: .funboard, alternates: [.midLength], rationale: reasons)
            }
            let pick = performancePick(skill: skill, cleanPowerful: cleanPowerful)
            reasons.append(cleanPowerful
                ? "Clean & powerful — \(pick.primary.displayName)."
                : "Soft / average — \(pick.primary.displayName).")
            return BoardTypeChoice(primary: pick.primary, alternates: pick.alternates, rationale: reasons)

        case 6...8:
            if beginnerish {
                reasons.append("Solid overhead — too much for now; forgiving board, mind the advisory.")
                return BoardTypeChoice(primary: .funboard, alternates: [.midLength], rationale: reasons)
            }
            reasons.append("Solid overhead — step-up.")
            return BoardTypeChoice(primary: .stepUp, alternates: advPlus ? [.hpsb, .gun] : [.shortboard], rationale: reasons)

        default: // > 8 ft
            if advPlus && p >= 13 {
                reasons.append("Big, long-period — gun.")
                return BoardTypeChoice(primary: .gun, alternates: [.stepUp], rationale: reasons)
            }
            reasons.append("Big surf beyond your level — forgiving board; do not paddle out if unsure.")
            return BoardTypeChoice(primary: .midLength, alternates: [.funboard], rationale: reasons)
        }
    }

    /// Convenience from a raw snapshot (no spot-shadowing). Used by the standalone sizing screen.
    func choose(conditions: ConditionsSnapshot, spot: Spot, skill: SkillLevel) -> BoardTypeChoice {
        let blown = BlownOutAdvisor().evaluate(conditions: conditions, spot: spot) != nil
        return choose(
            adjustedHeightFt: conditions.primarySwellHeightFt ?? 2.0,
            periodS: conditions.primarySwellPeriodS ?? 10.0,
            isBlownOut: blown,
            skill: skill
        )
    }

    /// In the 3–6 ft window: intermediates ride the daily driver / hybrid, advanced+ get the blade.
    private func performancePick(skill: SkillLevel, cleanPowerful: Bool) -> (primary: BoardType, alternates: [BoardType]) {
        switch skill {
        case .intermediate:
            return cleanPowerful
                ? (.shortboard, [.hpsb, .allRounder])
                : (.allRounder, [.shortboard])
        case .advanced, .expert:
            return cleanPowerful
                ? (.hpsb, [.shortboard, .stepUp])
                : (.shortboard, [.hpsb, .allRounder])
        case .beginner, .novice:
            return (.funboard, [.midLength])   // not reached (handled by caller), here for exhaustiveness
        }
    }
}
