import XCTest
@testable import Quiver

final class ConditionsParsingTests: XCTestCase {

    func testParseOpenMeteoMarineHourly() throws {
        let json = """
        {
          "hourly": {
            "time": ["2026-06-01T00:00","2026-06-01T01:00"],
            "wave_height": [1.2, 1.4],
            "wave_direction": [270, 268],
            "wave_period": [11.0, 11.5],
            "swell_wave_height": [1.0, 1.1],
            "swell_wave_period": [12.0, 12.2],
            "swell_wave_direction": [280, 282]
          }
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(OpenMeteoMarineProvider.MarineResponse.self, from: data)
        let parsed = OpenMeteoMarineProvider.parse(decoded, limit: 24)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].swellHeightM, 1.0)
        XCTAssertEqual(parsed[1].swellPeriodS, 12.2)
    }

    func testParseOpenMeteoWindHourly() throws {
        let json = """
        {
          "hourly": {
            "time": ["2026-06-01T00:00","2026-06-01T01:00"],
            "wind_speed_10m": [5.0, 7.2],
            "wind_direction_10m": [45, 55],
            "wind_gusts_10m": [10.0, 11.5]
          }
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(OpenMeteoWindProvider.WindResponse.self, from: data)
        let parsed = OpenMeteoWindProvider.parse(decoded, limit: 24)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].speedKt, 5.0)
        XCTAssertEqual(parsed[1].dirDeg, 55)
    }

    func testParseNDBCLatestObservation() {
        let txt = """
        #YY  MM DD hh mm WDIR WSPD GST  WVHT   DPD   APD MWD   PRES  ATMP  WTMP  DEWP  VIS PTDY  TIDE
        #yr  mo dy hr mn degT m/s  m/s   m     sec   sec degT  hPa   degC  degC  degC  nmi  hPa    ft
        2026 06 01 14 50 230 7.0  9.0  1.6  12.0  6.0  275 1015.0  17.0  15.5   MM   MM    MM    MM
        2026 06 01 14 40 232 7.2  9.5  1.6  12.0  6.0  274 1015.1  17.0  15.5   MM   MM    MM    MM
        """
        let obs = NDBCBuoyProvider.parseLatest(txt)
        XCTAssertNotNil(obs)
        XCTAssertEqual(obs?.waveHeightM, 1.6)
        XCTAssertEqual(obs?.dominantPeriodS, 12.0)
        XCTAssertEqual(obs?.meanDirDeg, 275)
        XCTAssertEqual(obs?.windDirDeg, 230)
    }

    func testParseNOAATidePredictions() throws {
        let json = """
        {
          "predictions": [
            {"t":"2026-06-01 00:00","v":"1.10"},
            {"t":"2026-06-01 01:00","v":"1.35"},
            {"t":"2026-06-01 02:00","v":"1.20"}
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode(NOAATidesProvider.PredictionsResponse.self, from: data)
        let preds = NOAATidesProvider.parse(decoded)
        XCTAssertEqual(preds.count, 3)
        XCTAssertEqual(preds[1].heightM, 1.35, accuracy: 0.0001)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(identifier: "GMT")
        let now = fmt.date(from: "2026-06-01 00:30")!
        let (h, trend) = NOAATidesProvider.currentHeightAndTrend(in: preds, now: now)
        XCTAssertEqual(try XCTUnwrap(h), 1.35, accuracy: 0.0001)
        XCTAssertEqual(trend, .falling)
    }

    func testCompositeMergeProducesAlignedSnapshots() {
        let now = Date()
        let marine: [HourlyMarine] = [
            HourlyMarine(time: now, waveHeightM: 1.0, waveDirDeg: 270, wavePeriodS: 11,
                         swellHeightM: 1.0, swellPeriodS: 12, swellDirDeg: 280),
            HourlyMarine(time: now.addingTimeInterval(3600), waveHeightM: 1.1, waveDirDeg: 271, wavePeriodS: 11,
                         swellHeightM: 1.05, swellPeriodS: 12, swellDirDeg: 281),
        ]
        let wind: [HourlyWind] = [
            HourlyWind(time: now, speedKt: 6, dirDeg: 40, gustKt: 10),
            HourlyWind(time: now.addingTimeInterval(3600), speedKt: 7, dirDeg: 42, gustKt: 11),
        ]
        let snaps = CompositeConditionsProvider.merge(spotId: "rincon-cove", marine: marine, wind: wind, tide: [], buoy: nil)
        XCTAssertEqual(snaps.count, 2)
        XCTAssertEqual(snaps[0].swellHeightM, 1.0)
        XCTAssertEqual(snaps[1].windSpeedKt, 7)
    }
}
