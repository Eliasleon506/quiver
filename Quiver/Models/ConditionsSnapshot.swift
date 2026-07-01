import Foundation

/// A point-in-time snapshot of conditions at a spot. In-memory only — not persisted.
struct ConditionsSnapshot: Codable, Hashable, Sendable {
    let spotId: String
    let timestamp: Date
    let fetchedAt: Date

    // Swell
    let swellHeightM: Double?
    let swellPeriodS: Double?
    let swellDirDeg: Double?

    // Combined sea state (when swell isn't broken out)
    let waveHeightM: Double?
    let wavePeriodS: Double?
    let waveDirDeg: Double?

    // Wind (kt = knots)
    let windSpeedKt: Double?
    let windDirDeg: Double?
    let windGustKt: Double?

    // Tide (meters above MLLW; trend is computed from the next prediction)
    let tideHeightM: Double?
    let tideTrend: TideTrend?

    // Sea-surface temperature (°C, from Open-Meteo Marine). Drives the wetsuit system (Phase 2).
    // Defaulted so existing call sites (tests, DimensionRecommenderView) keep compiling.
    var waterTempC: Double? = nil

    // Live buoy fallback (matches NDBC realtime fields)
    let buoyWaveHeightM: Double?
    let buoyDominantPeriodS: Double?
    let buoyMeanDirDeg: Double?

    static func empty(spotId: String, at date: Date = Date()) -> ConditionsSnapshot {
        ConditionsSnapshot(
            spotId: spotId, timestamp: date, fetchedAt: date,
            swellHeightM: nil, swellPeriodS: nil, swellDirDeg: nil,
            waveHeightM: nil, wavePeriodS: nil, waveDirDeg: nil,
            windSpeedKt: nil, windDirDeg: nil, windGustKt: nil,
            tideHeightM: nil, tideTrend: nil,
            waterTempC: nil,
            buoyWaveHeightM: nil, buoyDominantPeriodS: nil, buoyMeanDirDeg: nil
        )
    }

    var primarySwellHeightFt: Double? {
        (swellHeightM ?? waveHeightM).map { $0 * 3.28084 }
    }

    var primarySwellPeriodS: Double? { swellPeriodS ?? wavePeriodS }
    var primarySwellDirDeg: Double? { swellDirDeg ?? waveDirDeg }

    /// Tide height in feet (NOAA predictions are stored in meters above MLLW).
    var tideHeightFt: Double? { tideHeightM.map { $0 * 3.28084 } }

    /// Sea-surface temperature in °F.
    var waterTempF: Double? { waterTempC.map { $0 * 9 / 5 + 32 } }
}
