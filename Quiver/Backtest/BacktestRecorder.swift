import Foundation
import SwiftData

/// Turns the app into its own forecast-verification harness. It persists the Open-Meteo wave
/// predictions for future hours, then — once those hours arrive — reconciles them against the live
/// NDBC buoy reading already merged into `ConditionsSnapshot`. No provider changes: both the
/// prediction and the actual ride along on the same snapshot type.
@MainActor
struct BacktestRecorder {
    let context: ModelContext

    /// ±60 min window for matching a buoy observation to a stored prediction's valid hour.
    private static let matchWindow: TimeInterval = 60 * 60

    /// Capture predictions for the *future* hours of a freshly fetched forecast. One record per
    /// (spotId, validTime); an hour we've already captured is left alone (keeps the longest lead).
    func capture(forecast: [ConditionsSnapshot], now: Date = Date()) {
        for snap in forecast where snap.timestamp > now {
            guard let predM = snap.swellHeightM ?? snap.waveHeightM else { continue }
            if fetchRecord(spotId: snap.spotId, validTime: snap.timestamp) != nil { continue }
            context.insert(
                ForecastRecord(
                    spotId: snap.spotId,
                    validTime: snap.timestamp,
                    recordedAt: now,
                    predictedWaveHeightM: predM,
                    predictedPeriodS: snap.swellPeriodS ?? snap.wavePeriodS
                )
            )
        }
        try? context.save()
    }

    /// Reconcile a live buoy reading onto the unresolved record whose `validTime` is closest to
    /// (and within ±60 min of) `observedAt`.
    func reconcile(spotId: String, observedAt: Date, buoyWaveHeightM: Double?, buoyPeriodS: Double?) {
        guard let actualM = buoyWaveHeightM else { return }
        let lower = observedAt.addingTimeInterval(-Self.matchWindow)
        let upper = observedAt.addingTimeInterval(Self.matchWindow)
        let descriptor = FetchDescriptor<ForecastRecord>(
            predicate: #Predicate {
                $0.spotId == spotId && !$0.isResolved && $0.validTime >= lower && $0.validTime <= upper
            }
        )
        guard let matches = try? context.fetch(descriptor), !matches.isEmpty else { return }
        let best = matches.min {
            abs($0.validTime.timeIntervalSince(observedAt)) < abs($1.validTime.timeIntervalSince(observedAt))
        }!
        best.actualWaveHeightM = actualM
        best.actualPeriodS = buoyPeriodS
        best.isResolved = true
        try? context.save()
    }

    /// Convenience: reconcile straight from a current snapshot that already carries the buoy reading.
    func reconcile(current: ConditionsSnapshot) {
        reconcile(
            spotId: current.spotId,
            observedAt: current.timestamp,
            buoyWaveHeightM: current.buoyWaveHeightM,
            buoyPeriodS: current.buoyDominantPeriodS
        )
    }

    private func fetchRecord(spotId: String, validTime: Date) -> ForecastRecord? {
        let descriptor = FetchDescriptor<ForecastRecord>(
            predicate: #Predicate { $0.spotId == spotId && $0.validTime == validTime }
        )
        return try? context.fetch(descriptor).first
    }
}
