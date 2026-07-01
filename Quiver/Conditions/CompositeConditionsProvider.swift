import Foundation

/// Fans out to Marine + Wind + Buoy + Tide providers and merges results
/// into a single `ConditionsSnapshot` (current) and forecast array.
actor CompositeConditionsProvider: ConditionsProvider {
    /// Shared instance so all screens reuse the same 30-min per-spot cache.
    static let shared = CompositeConditionsProvider()

    private let marine: OpenMeteoMarineProvider
    private let wind: OpenMeteoWindProvider
    private let buoy: NDBCBuoyProvider
    private let tides: NOAATidesProvider
    private let cacheTTL: TimeInterval = 30 * 60

    private struct CacheEntry {
        let snapshot: ConditionsSnapshot
        let forecast: [ConditionsSnapshot]
        let storedAt: Date
    }
    private var cache: [String: CacheEntry] = [:]

    init(
        marine: OpenMeteoMarineProvider = OpenMeteoMarineProvider(),
        wind: OpenMeteoWindProvider = OpenMeteoWindProvider(),
        buoy: NDBCBuoyProvider = NDBCBuoyProvider(),
        tides: NOAATidesProvider = NOAATidesProvider()
    ) {
        self.marine = marine
        self.wind = wind
        self.buoy = buoy
        self.tides = tides
    }

    func currentConditions(spot: Spot) async throws -> ConditionsSnapshot {
        if let cached = cache[spot.id], Date().timeIntervalSince(cached.storedAt) < cacheTTL {
            return cached.snapshot
        }
        let forecast = try await loadForecast(spot: spot, hours: 48)
        return forecast.first ?? .empty(spotId: spot.id)
    }

    func forecast(spot: Spot, hours: Int) async throws -> [ConditionsSnapshot] {
        if let cached = cache[spot.id],
           Date().timeIntervalSince(cached.storedAt) < cacheTTL,
           cached.forecast.count >= hours {
            return Array(cached.forecast.prefix(hours))
        }
        return try await loadForecast(spot: spot, hours: hours)
    }

    private func loadForecast(spot: Spot, hours: Int) async throws -> [ConditionsSnapshot] {
        async let marineHourly = marine.fetch(lat: spot.lat, lon: spot.lon, hours: hours)
        async let windHourly = wind.fetch(lat: spot.lat, lon: spot.lon, hours: hours)
        async let tidePreds = fetchTides(stationId: spot.tideStationId, hours: hours)
        async let buoyObs = fetchBuoy(stationId: spot.ndbcBuoyId)

        let m = try await marineHourly
        let w = try await windHourly
        let t = await tidePreds
        let b = await buoyObs

        let snapshots = Self.merge(spotId: spot.id, marine: m, wind: w, tide: t, buoy: b)
        cache[spot.id] = CacheEntry(
            snapshot: snapshots.first ?? .empty(spotId: spot.id),
            forecast: snapshots,
            storedAt: Date()
        )
        return snapshots
    }

    private func fetchTides(stationId: String?, hours: Int) async -> [NOAATidesProvider.TidePrediction] {
        guard let id = stationId else { return [] }
        return (try? await tides.predictions(stationId: id, hours: hours)) ?? []
    }

    private func fetchBuoy(stationId: String?) async -> NDBCBuoyProvider.Observation? {
        guard let id = stationId else { return nil }
        return try? await buoy.latest(stationId: id)
    }

    static func merge(
        spotId: String,
        marine: [HourlyMarine],
        wind: [HourlyWind],
        tide: [NOAATidesProvider.TidePrediction],
        buoy: NDBCBuoyProvider.Observation?
    ) -> [ConditionsSnapshot] {
        let count = min(marine.count, wind.count)
        var out: [ConditionsSnapshot] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let m = marine[i]
            let w = wind[i]
            let (tideH, trend) = NOAATidesProvider.currentHeightAndTrend(in: tide, now: m.time)
            out.append(ConditionsSnapshot(
                spotId: spotId,
                timestamp: m.time,
                fetchedAt: Date(),
                swellHeightM: m.swellHeightM,
                swellPeriodS: m.swellPeriodS,
                swellDirDeg: m.swellDirDeg,
                waveHeightM: m.waveHeightM,
                wavePeriodS: m.wavePeriodS,
                waveDirDeg: m.waveDirDeg,
                windSpeedKt: w.speedKt,
                windDirDeg: w.dirDeg,
                windGustKt: w.gustKt,
                tideHeightM: tideH,
                tideTrend: trend,
                waterTempC: m.seaTemperatureC,
                buoyWaveHeightM: i == 0 ? buoy?.waveHeightM : nil,
                buoyDominantPeriodS: i == 0 ? buoy?.dominantPeriodS : nil,
                buoyMeanDirDeg: i == 0 ? buoy?.meanDirDeg : nil
            ))
        }
        return out
    }
}
