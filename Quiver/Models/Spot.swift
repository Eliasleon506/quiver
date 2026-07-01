import Foundation
import CoreLocation

/// Spots are seeded from a bundle JSON and not persisted in SwiftData (read-only for MVP).
struct Spot: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let region: SpotRegion
    let ndbcBuoyId: String?
    let tideStationId: String?
    let optimalSwellDirMinDeg: Double
    let optimalSwellDirMaxDeg: Double
    let favorableWindDirMinDeg: Double
    let favorableWindDirMaxDeg: Double
    /// How the spot breaks. Defaults keep older JSON / direct call sites decoding cleanly.
    let waveCharacter: WaveCharacter
    let tidePreference: TidePreference
    let notes: String?

    init(
        id: String, name: String, lat: Double, lon: Double, region: SpotRegion,
        ndbcBuoyId: String?, tideStationId: String?,
        optimalSwellDirMinDeg: Double, optimalSwellDirMaxDeg: Double,
        favorableWindDirMinDeg: Double, favorableWindDirMaxDeg: Double,
        waveCharacter: WaveCharacter = .performancePoint,
        tidePreference: TidePreference = .allTides,
        notes: String?
    ) {
        self.id = id; self.name = name; self.lat = lat; self.lon = lon; self.region = region
        self.ndbcBuoyId = ndbcBuoyId; self.tideStationId = tideStationId
        self.optimalSwellDirMinDeg = optimalSwellDirMinDeg
        self.optimalSwellDirMaxDeg = optimalSwellDirMaxDeg
        self.favorableWindDirMinDeg = favorableWindDirMinDeg
        self.favorableWindDirMaxDeg = favorableWindDirMaxDeg
        self.waveCharacter = waveCharacter
        self.tidePreference = tidePreference
        self.notes = notes
    }

    /// Defaulted decoding so JSON entries missing the new fields still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        region = try c.decode(SpotRegion.self, forKey: .region)
        ndbcBuoyId = try c.decodeIfPresent(String.self, forKey: .ndbcBuoyId)
        tideStationId = try c.decodeIfPresent(String.self, forKey: .tideStationId)
        optimalSwellDirMinDeg = try c.decode(Double.self, forKey: .optimalSwellDirMinDeg)
        optimalSwellDirMaxDeg = try c.decode(Double.self, forKey: .optimalSwellDirMaxDeg)
        favorableWindDirMinDeg = try c.decode(Double.self, forKey: .favorableWindDirMinDeg)
        favorableWindDirMaxDeg = try c.decode(Double.self, forKey: .favorableWindDirMaxDeg)
        waveCharacter = try c.decodeIfPresent(WaveCharacter.self, forKey: .waveCharacter) ?? .performancePoint
        tidePreference = try c.decodeIfPresent(TidePreference.self, forKey: .tidePreference) ?? .allTides
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Convenience accessor; flat min/max stays the source of truth for wrap-aware math.
    var optimalSwellDirDeg: ClosedRange<Double> {
        optimalSwellDirMinDeg <= optimalSwellDirMaxDeg
            ? optimalSwellDirMinDeg...optimalSwellDirMaxDeg
            : optimalSwellDirMaxDeg...optimalSwellDirMinDeg
    }

    /// Returns true when the swell direction (in deg) is within this spot's optimal window.
    func isSwellAligned(_ swellDirDeg: Double) -> Bool {
        Self.isAngleInRange(swellDirDeg, min: optimalSwellDirMinDeg, max: optimalSwellDirMaxDeg)
    }

    /// Returns true when the wind direction is in the spot's "offshore-ish" window.
    func isWindFavorable(_ windDirDeg: Double) -> Bool {
        Self.isAngleInRange(windDirDeg, min: favorableWindDirMinDeg, max: favorableWindDirMaxDeg)
    }

    /// 0 when the swell is inside the optimal window, else the smaller wrap-aware angular
    /// distance (deg) to the nearer window bound. Drives the island-shadowing gate.
    func degreesOutsideWindow(_ swellDirDeg: Double) -> Double {
        guard !isSwellAligned(swellDirDeg) else { return 0 }
        let toMin = Self.angularDistance(swellDirDeg, optimalSwellDirMinDeg)
        let toMax = Self.angularDistance(swellDirDeg, optimalSwellDirMaxDeg)
        return Swift.min(toMin, toMax)
    }

    private static func isAngleInRange(_ angle: Double, min: Double, max: Double) -> Bool {
        let a = norm(angle), lo = norm(min), hi = norm(max)
        return lo <= hi ? (a >= lo && a <= hi) : (a >= lo || a <= hi)
    }

    /// Shortest distance between two compass bearings, accounting for 360° wrap (0...180).
    private static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(norm(a) - norm(b)).truncatingRemainder(dividingBy: 360)
        return Swift.min(d, 360 - d)
    }

    private static func norm(_ deg: Double) -> Double {
        ((deg.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
    }
}
