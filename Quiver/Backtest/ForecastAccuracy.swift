import Foundation

/// Pure, deterministic verification math over resolved `ForecastRecord`s — no SwiftData, no network,
/// so it is fully unit-testable. Wave-height error is reported in **feet** (what surfers read);
/// period error in seconds.
enum ForecastAccuracy {

    struct Summary: Equatable {
        var sampleCount: Int
        /// Mean absolute error of predicted vs. actual wave height, in feet.
        var waveHeightMAEft: Double
        /// Mean signed error (predicted − actual), in feet. Positive ⇒ tends to over-forecast.
        var waveHeightBiasFt: Double
        /// Mean absolute period error, in seconds, over samples that have both periods.
        var periodMAEs: Double
        var periodSampleCount: Int

        static let empty = Summary(sampleCount: 0, waveHeightMAEft: 0, waveHeightBiasFt: 0,
                                   periodMAEs: 0, periodSampleCount: 0)
    }

    /// Summarize resolved records (records still awaiting their forecast hour are ignored).
    static func summarize(_ records: [ForecastRecord]) -> Summary {
        let resolved = records.filter { $0.isResolved && $0.actualWaveHeightM != nil }
        guard !resolved.isEmpty else { return .empty }

        let heightErrsFt = resolved.map {
            ($0.predictedWaveHeightM - ($0.actualWaveHeightM ?? 0)) * 3.28084
        }
        let mae = heightErrsFt.map(abs).reduce(0, +) / Double(heightErrsFt.count)
        let bias = heightErrsFt.reduce(0, +) / Double(heightErrsFt.count)

        let periodErrs = resolved.compactMap { r -> Double? in
            guard let p = r.predictedPeriodS, let a = r.actualPeriodS else { return nil }
            return abs(p - a)
        }
        let periodMAE = periodErrs.isEmpty ? 0 : periodErrs.reduce(0, +) / Double(periodErrs.count)

        return Summary(
            sampleCount: resolved.count,
            waveHeightMAEft: mae,
            waveHeightBiasFt: bias,
            periodMAEs: periodMAE,
            periodSampleCount: periodErrs.count
        )
    }

    /// Per-spot breakdown, sorted by spot id; spots with no resolved samples are dropped.
    static func bySpot(_ records: [ForecastRecord]) -> [(spotId: String, summary: Summary)] {
        Dictionary(grouping: records, by: \.spotId)
            .map { (spotId: $0.key, summary: summarize($0.value)) }
            .filter { $0.summary.sampleCount > 0 }
            .sorted { $0.spotId < $1.spotId }
    }
}
