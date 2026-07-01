import Foundation

/// NOAA NDBC realtime buoy text feed. Parses the latest observation.
/// Feed: https://www.ndbc.noaa.gov/data/realtime2/{stationId}.txt
struct NDBCBuoyProvider: Sendable {
    private let fetcher: JSONFetcher

    init(fetcher: JSONFetcher = JSONFetcher()) { self.fetcher = fetcher }

    struct Observation: Sendable {
        let time: Date
        let waveHeightM: Double?
        let dominantPeriodS: Double?
        let meanDirDeg: Double?
        let windSpeedKt: Double?
        let windDirDeg: Double?
    }

    func latest(stationId: String) async throws -> Observation? {
        let url = URL(string: "https://www.ndbc.noaa.gov/data/realtime2/\(stationId).txt")!
        let text = try await fetcher.getText(url)
        return Self.parseLatest(text)
    }

    /// Header layout (.txt feed):
    /// #YY MM DD hh mm WDIR WSPD GST WVHT DPD APD MWD PRES ATMP WTMP DEWP VIS PTDY TIDE
    /// Units row starts with `#yr`. Values: MM = missing.
    static func parseLatest(_ raw: String) -> Observation? {
        let lines = raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        guard let first = lines.first(where: { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return nil
        }
        let cols = first.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard cols.count >= 9 else { return nil }

        func d(_ s: String) -> Double? {
            if s == "MM" || s == "-" { return nil }
            return Double(s)
        }
        let year = Int(cols[0]) ?? 1970
        let month = Int(cols[1]) ?? 1
        let day = Int(cols[2]) ?? 1
        let hour = Int(cols[3]) ?? 0
        let minute = Int(cols[4]) ?? 0
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        comps.timeZone = TimeZone(identifier: "UTC")
        let time = Calendar(identifier: .gregorian).date(from: comps) ?? Date()

        let windDir = d(cols[5])
        let windSpdMps = d(cols[6])
        let wvht = cols.count > 8 ? d(cols[8]) : nil
        let dpd  = cols.count > 9 ? d(cols[9]) : nil
        let mwd  = cols.count > 11 ? d(cols[11]) : nil

        return Observation(
            time: time,
            waveHeightM: wvht,
            dominantPeriodS: dpd,
            meanDirDeg: mwd,
            windSpeedKt: windSpdMps.map { $0 * 1.94384 },
            windDirDeg: windDir
        )
    }
}
