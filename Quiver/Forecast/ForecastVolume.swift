import Foundation

/// Turns a forecast (hourly `ConditionsSnapshot`s) into one minimum recommended
/// board volume per day. The minimum is the low end of the recommender's target
/// range, computed from each day's *peak-quality* hour so a small clean day isn't
/// sized like a big one. Pure/static so it's unit-testable without SwiftData.
struct ForecastVolume {
    struct DailyMin: Identifiable, Sendable {
        let date: Date
        let swellFt: Double?
        let periodS: Double?
        let range: VolumeRange
        var id: Date { date }
        var minVolumeL: Double { range.lowL }
    }

    static func dailyMinimums(
        snapshots: [ConditionsSnapshot],
        spot: Spot,
        weightKg: Double,
        skill: SkillLevel,
        age: Int,
        calendar: Calendar = .current,
        maxDays: Int = 7,
        volumeCalculator: VolumeCalculator = VolumeCalculator(),
        advisor: BlownOutAdvisor = BlownOutAdvisor()
    ) -> [DailyMin] {
        guard !snapshots.isEmpty else { return [] }

        let groups = Dictionary(grouping: snapshots) { calendar.startOfDay(for: $0.timestamp) }
        let days = groups.keys.sorted().prefix(maxDays)

        return days.compactMap { day -> DailyMin? in
            guard let daySnaps = groups[day], !daySnaps.isEmpty else { return nil }
            // Representative hour = the session you'd actually pick that day.
            guard let peak = daySnaps.max(by: {
                ForecastQuality.score($0, spot: spot) < ForecastQuality.score($1, spot: spot)
            }) else { return nil }

            let advisory = advisor.evaluate(conditions: peak, spot: spot)
            let range = volumeCalculator.targetVolume(
                weightKg: weightKg,
                skill: skill,
                age: age,
                conditions: peak,
                advisory: advisory
            )
            return DailyMin(
                date: day,
                swellFt: peak.primarySwellHeightFt,
                periodS: peak.primarySwellPeriodS,
                range: range
            )
        }
    }
}
