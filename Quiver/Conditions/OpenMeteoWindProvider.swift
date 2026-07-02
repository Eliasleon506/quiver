import Foundation

/// Open-Meteo Forecast — surface wind. No API key. Wind values returned in knots.
struct OpenMeteoWindProvider: Sendable {
    private let fetcher: JSONFetcher

    init(fetcher: JSONFetcher = JSONFetcher()) { self.fetcher = fetcher }

    struct WindResponse: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let wind_speed_10m: [Double?]?
            let wind_direction_10m: [Double?]?
            let wind_gusts_10m: [Double?]?
        }
        let hourly: Hourly
    }

    func fetch(lat: Double, lon: Double, hours: Int) async throws -> [HourlyWind] {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "hourly", value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(max(1, min(7, Int(ceil(Double(hours)/24)))))),
        ]
        let resp: WindResponse = try await fetcher.get(comps.url!)
        return Self.parse(resp, limit: hours)
    }

    static func parse(_ resp: WindResponse, limit: Int) -> [HourlyWind] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let plain = DateFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")   // fixed-format parsing must ignore device locale/calendar
        plain.dateFormat = "yyyy-MM-dd'T'HH:mm"
        plain.timeZone = TimeZone(secondsFromGMT: 0)

        let times: [Date] = resp.hourly.time.map { iso.date(from: $0) ?? plain.date(from: $0) ?? Date() }
        let count = min(times.count, limit)
        var out: [HourlyWind] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            out.append(HourlyWind(
                time: times[i],
                speedKt: resp.hourly.wind_speed_10m?[safe: i] ?? nil,
                dirDeg: resp.hourly.wind_direction_10m?[safe: i] ?? nil,
                gustKt: resp.hourly.wind_gusts_10m?[safe: i] ?? nil
            ))
        }
        return out
    }
}

struct HourlyWind: Sendable {
    let time: Date
    let speedKt: Double?
    let dirDeg: Double?
    let gustKt: Double?
}
