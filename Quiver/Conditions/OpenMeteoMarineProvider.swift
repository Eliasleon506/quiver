import Foundation

/// Open-Meteo Marine — wave/swell forecast. No API key.
struct OpenMeteoMarineProvider: Sendable {
    private let fetcher: JSONFetcher

    init(fetcher: JSONFetcher = JSONFetcher()) { self.fetcher = fetcher }

    struct MarineResponse: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let wave_height: [Double?]?
            let wave_direction: [Double?]?
            let wave_period: [Double?]?
            let swell_wave_height: [Double?]?
            let swell_wave_period: [Double?]?
            let swell_wave_direction: [Double?]?
            let sea_surface_temperature: [Double?]?
        }
        let hourly: Hourly
    }

    func fetch(lat: Double, lon: Double, hours: Int) async throws -> [HourlyMarine] {
        var comps = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "hourly", value: "wave_height,wave_direction,wave_period,swell_wave_height,swell_wave_period,swell_wave_direction,sea_surface_temperature"),
            URLQueryItem(name: "length_unit", value: "metric"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(max(1, min(7, Int(ceil(Double(hours)/24)))))),
        ]
        let url = comps.url!
        let resp: MarineResponse = try await fetcher.get(url)
        return Self.parse(resp, limit: hours)
    }

    static func parse(_ resp: MarineResponse, limit: Int) -> [HourlyMarine] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let altFormatter = ISO8601DateFormatter()
        altFormatter.formatOptions = [.withInternetDateTime]
        let plain = DateFormatter()
        plain.dateFormat = "yyyy-MM-dd'T'HH:mm"
        plain.timeZone = TimeZone(secondsFromGMT: 0)

        let times: [Date] = resp.hourly.time.map { s in
            isoFormatter.date(from: s) ?? altFormatter.date(from: s) ?? plain.date(from: s) ?? Date()
        }
        let count = min(times.count, limit)
        var out: [HourlyMarine] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            out.append(HourlyMarine(
                time: times[i],
                waveHeightM: resp.hourly.wave_height?[safe: i] ?? nil,
                waveDirDeg: resp.hourly.wave_direction?[safe: i] ?? nil,
                wavePeriodS: resp.hourly.wave_period?[safe: i] ?? nil,
                swellHeightM: resp.hourly.swell_wave_height?[safe: i] ?? nil,
                swellPeriodS: resp.hourly.swell_wave_period?[safe: i] ?? nil,
                swellDirDeg: resp.hourly.swell_wave_direction?[safe: i] ?? nil,
                seaTemperatureC: resp.hourly.sea_surface_temperature?[safe: i] ?? nil
            ))
        }
        return out
    }
}

struct HourlyMarine: Sendable {
    let time: Date
    let waveHeightM: Double?
    let waveDirDeg: Double?
    let wavePeriodS: Double?
    let swellHeightM: Double?
    let swellPeriodS: Double?
    let swellDirDeg: Double?
    var seaTemperatureC: Double? = nil
}

extension Array {
    subscript(safe i: Int) -> Element? { (i >= 0 && i < count) ? self[i] : nil }
}
