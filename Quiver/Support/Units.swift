import Foundation

enum Units {
    static func metersToFeet(_ m: Double) -> Double { m * 3.28084 }
    static func metersPerSecondToKnots(_ mps: Double) -> Double { mps * 1.94384 }
    static func feetToInches(_ ft: Double) -> Double { ft * 12 }

    /// "5'10"" formatted from total inches.
    static func feetInchesString(fromInches totalInches: Double) -> String {
        let feet = Int(totalInches) / 12
        let inches = Int(totalInches.rounded()) % 12
        return "\(feet)'\(inches)\""
    }

    static func compassPoint(degrees: Double) -> String {
        let points = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let idx = Int(((degrees / 22.5) + 0.5).rounded(.down)) & 15
        return points[idx]
    }
}
