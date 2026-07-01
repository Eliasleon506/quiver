import Foundation

/// Transparent, tunable per-hour surf-quality scoring used for the forecast view's
/// "best window today" highlight. Returns 0..1 where higher is a better session.
struct ForecastQuality: Sendable {

    struct ScoredSnapshot: Sendable, Identifiable {
        let snapshot: ConditionsSnapshot
        let score: Double
        var id: Date { snapshot.timestamp }
    }

    struct Window: Sendable {
        let start: Date
        let end: Date
        let peakScore: Double
    }

    /// Component breakdown is intentionally simple so it's easy to tune from data later.
    static func score(_ s: ConditionsSnapshot, spot: Spot) -> Double {
        let height = s.primarySwellHeightFt ?? 0
        let period = s.primarySwellPeriodS ?? 0
        let windKt = s.windSpeedKt ?? 0
        let windDir = s.windDirDeg ?? 0
        let swellDir = s.primarySwellDirDeg ?? 0

        // Height: best in the 3–6 ft band, still good through head-high+, weak when tiny.
        let heightScore: Double
        switch height {
        case ..<1: heightScore = 0.10
        case ..<2: heightScore = 0.45
        case ..<6.0001: heightScore = 1.0
        case ..<9.0001: heightScore = 0.82
        default: heightScore = 0.6
        }

        // Period: 6s → poor, ~16s+ → excellent.
        let periodScore = min(1.0, max(0.2, (period - 6.0) / 10.0))

        // Wind: glassy is best regardless of direction; otherwise reward offshore-ish,
        // penalize onshore, and scale down as it strengthens.
        let windScore: Double
        if windKt <= 4 {
            windScore = 1.0
        } else if spot.isWindFavorable(windDir) {
            windScore = max(0.5, 1.0 - windKt / 40.0)
        } else {
            windScore = max(0.1, 0.8 - windKt / 20.0)
        }

        // Swell direction alignment with the spot's window.
        let alignScore = spot.isSwellAligned(swellDir) ? 1.0 : 0.5

        let raw = heightScore * 0.35
                + periodScore * 0.15
                + windScore   * 0.35
                + alignScore  * 0.15
        return min(1.0, max(0.0, raw))
    }

    static func scored(_ snaps: [ConditionsSnapshot], spot: Spot) -> [ScoredSnapshot] {
        snaps.map { ScoredSnapshot(snapshot: $0, score: score($0, spot: spot)) }
    }

    /// Best contiguous block of hours *today* (from roughly now onward), defined as the
    /// run containing the peak hour where each hour scores within `tolerance` of the peak.
    static func bestWindowToday(
        _ snaps: [ConditionsSnapshot],
        spot: Spot,
        now: Date = Date(),
        tolerance: Double = 0.1,
        calendar: Calendar = .current
    ) -> Window? {
        let todays = snaps
            .filter {
                calendar.isDate($0.timestamp, inSameDayAs: now)
                && $0.timestamp >= now.addingTimeInterval(-3600)
            }
            .sorted { $0.timestamp < $1.timestamp }
        guard !todays.isEmpty else { return nil }

        let scoredHours = todays.map { (snap: $0, score: score($0, spot: spot)) }
        guard let peakIndex = scoredHours.indices.max(by: { scoredHours[$0].score < scoredHours[$1].score }) else {
            return nil
        }
        let peak = scoredHours[peakIndex].score

        // Expand left and right while within tolerance of the peak.
        var lo = peakIndex
        while lo - 1 >= 0, scoredHours[lo - 1].score >= peak - tolerance { lo -= 1 }
        var hi = peakIndex
        while hi + 1 < scoredHours.count, scoredHours[hi + 1].score >= peak - tolerance { hi += 1 }

        let start = scoredHours[lo].snap.timestamp
        // End at the next hour boundary so a single-hour window still has visible width.
        let end = scoredHours[hi].snap.timestamp.addingTimeInterval(3600)
        return Window(start: start, end: end, peakScore: peak)
    }

    static func label(forScore score: Double) -> String {
        switch score {
        case ..<0.35: "Poor"
        case ..<0.55: "Fair"
        case ..<0.72: "Good"
        case ..<0.86: "Very good"
        default: "Epic"
        }
    }
}
