import Foundation
import SwiftData

/// A single forecast-verification sample: what the app *predicted* for one spot at one valid hour,
/// and — once that hour arrives — what the live NDBC buoy *actually* measured. Aggregated by
/// `ForecastAccuracy` into per-spot error stats. Persisted so skill accrues across launches.
@Model
final class ForecastRecord {
    @Attribute(.unique) var id: UUID
    var spotId: String
    /// The hour this prediction is *for*.
    var validTime: Date
    /// When the prediction was captured (drives lead time).
    var recordedAt: Date
    /// `validTime − recordedAt`, in hours — how far ahead the forecast was made.
    var leadTimeHours: Double

    var predictedWaveHeightM: Double
    var predictedPeriodS: Double?

    /// Filled in at reconcile time from the live buoy reading; `nil` until the hour passes.
    var actualWaveHeightM: Double?
    var actualPeriodS: Double?
    var isResolved: Bool

    init(
        id: UUID = UUID(),
        spotId: String,
        validTime: Date,
        recordedAt: Date = Date(),
        predictedWaveHeightM: Double,
        predictedPeriodS: Double? = nil
    ) {
        self.id = id
        self.spotId = spotId
        self.validTime = validTime
        self.recordedAt = recordedAt
        self.leadTimeHours = validTime.timeIntervalSince(recordedAt) / 3600
        self.predictedWaveHeightM = predictedWaveHeightM
        self.predictedPeriodS = predictedPeriodS
        self.actualWaveHeightM = nil
        self.actualPeriodS = nil
        self.isResolved = false
    }

    var predictedWaveHeightFt: Double { predictedWaveHeightM * 3.28084 }
    var actualWaveHeightFt: Double? { actualWaveHeightM.map { $0 * 3.28084 } }
}
