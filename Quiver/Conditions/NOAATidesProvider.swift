import Foundation

/// NOAA CO-OPS Tides & Currents predictions API.
struct NOAATidesProvider: Sendable {
    private let fetcher: JSONFetcher

    init(fetcher: JSONFetcher = JSONFetcher()) { self.fetcher = fetcher }

    struct PredictionsResponse: Decodable {
        struct Item: Decodable {
            let t: String
            let v: String
        }
        let predictions: [Item]?
    }

    struct TidePrediction: Sendable {
        let time: Date
        let heightM: Double
    }

    func predictions(stationId: String, hours: Int) async throws -> [TidePrediction] {
        var comps = URLComponents(string: "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter")!
        let begin = Date()
        let end = Calendar.current.date(byAdding: .hour, value: max(1, hours), to: begin) ?? begin
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd HH:mm"
        dateFmt.timeZone = TimeZone(identifier: "GMT")
        comps.queryItems = [
            URLQueryItem(name: "product", value: "predictions"),
            URLQueryItem(name: "application", value: "Quiver"),
            URLQueryItem(name: "begin_date", value: dateFmt.string(from: begin)),
            URLQueryItem(name: "end_date", value: dateFmt.string(from: end)),
            URLQueryItem(name: "datum", value: "MLLW"),
            URLQueryItem(name: "station", value: stationId),
            URLQueryItem(name: "time_zone", value: "gmt"),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "interval", value: "h"),
            URLQueryItem(name: "format", value: "json"),
        ]
        let resp: PredictionsResponse = try await fetcher.get(comps.url!)
        return Self.parse(resp)
    }

    static func parse(_ resp: PredictionsResponse) -> [TidePrediction] {
        guard let items = resp.predictions else { return [] }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(identifier: "GMT")
        return items.compactMap { item in
            guard let v = Double(item.v), let t = fmt.date(from: item.t) else { return nil }
            return TidePrediction(time: t, heightM: v)
        }
    }

    static func currentHeightAndTrend(in predictions: [TidePrediction], now: Date = Date()) -> (Double?, TideTrend?) {
        guard !predictions.isEmpty else { return (nil, nil) }
        let sorted = predictions.sorted(by: { $0.time < $1.time })
        let idx = sorted.firstIndex(where: { $0.time >= now }) ?? max(0, sorted.count - 1)
        let current = sorted[idx]
        let trend: TideTrend?
        if idx + 1 < sorted.count {
            let next = sorted[idx + 1]
            let delta = next.heightM - current.heightM
            trend = abs(delta) < 0.02 ? .slack : (delta > 0 ? .rising : .falling)
        } else if idx > 0 {
            let prev = sorted[idx - 1]
            let delta = current.heightM - prev.heightM
            trend = abs(delta) < 0.02 ? .slack : (delta > 0 ? .rising : .falling)
        } else {
            trend = nil
        }
        return (current.heightM, trend)
    }
}
