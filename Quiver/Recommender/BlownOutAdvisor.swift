import Foundation

// Advisory model + priority resolver.
// (File keeps its original name; `BlownOutAdvisor` is now one of several advisories produced here.)

/// Severity ranks the advisories so the engine can surface the single most important one.
enum AdvisorySeverity: Int, Comparable, Sendable {
    case informational = 1   // tide / island-shadowing nuance
    case severe = 2          // blown out — un-surfable
    case danger = 3          // above skill level — safety

    static func < (l: AdvisorySeverity, r: AdvisorySeverity) -> Bool { l.rawValue < r.rawValue }

    /// Stable string token used in the Gemini structured-output schema.
    var apiValue: String {
        switch self {
        case .informational: "informational"
        case .severe: "severe"
        case .danger: "danger"
        }
    }

    /// Decode from the Gemini schema token; unknown values fall back to informational.
    init(apiValue: String) {
        switch apiValue.lowercased() {
        case "danger": self = .danger
        case "severe": self = .severe
        default: self = .informational
        }
    }
}

struct Advisory: Sendable, Equatable {
    let title: String
    let detail: String
    let severity: AdvisorySeverity
}

/// Builds the candidate advisories and resolves them by priority. Each gate's mechanical effect
/// (height cut, volume bump, board downgrade, forgiving bias) is applied by the `Recommender`
/// regardless of which advisory ultimately wins the single banner slot.
enum AdvisoryFactory {
    static func aboveSkillLevel() -> Advisory {
        Advisory(
            title: "Above Skill Level",
            detail: "Conditions are heavy today. If you go, stick to the inside whitewash or watch from the beach.",
            severity: .danger
        )
    }

    static func blownOut(windKt: Double) -> Advisory {
        Advisory(
            title: "Blown Out",
            detail: "Strong onshore winds (\(Int(windKt.rounded())) kt) are wrecking the conditions. Expect messy, choppy surf.",
            severity: .severe
        )
    }

    static func swellShadowed() -> Advisory {
        Advisory(
            title: "Swell Shadowed",
            detail: "The islands are blocking the main swell energy. It will be much smaller here than the raw forecast.",
            severity: .informational
        )
    }

    static func tideSwamped() -> Advisory {
        Advisory(
            title: "Tide Swamped",
            detail: "The tide is too high for this spot right now. Waves will be soft and hard to catch.",
            severity: .informational
        )
    }

    /// Highest-severity advisory wins the banner; `nil` when nothing triggered.
    static func resolve(_ advisories: [Advisory]) -> Advisory? {
        advisories.max(by: { $0.severity < $1.severity })
    }
}

/// Thin producer of the "Blown Out" advisory from raw conditions + spot. Shared by the
/// `Recommender` wind gate and the `ForecastVolume` per-day sizing.
struct BlownOutAdvisor: Sendable {
    func evaluate(conditions: ConditionsSnapshot, spot: Spot) -> Advisory? {
        let windKt = conditions.windSpeedKt ?? 0
        let windDir = conditions.windDirDeg ?? 0
        let onshore = !spot.isWindFavorable(windDir)
        if windKt >= 20 { return AdvisoryFactory.blownOut(windKt: windKt) }       // heavy regardless
        if onshore && windKt > 12 { return AdvisoryFactory.blownOut(windKt: windKt) }
        return nil
    }
}
