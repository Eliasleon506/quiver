import Foundation

/// Onboarding skill quiz — 11 questions, additive 110-point scale. Point values are
/// intentionally tuned to weight fundamentals (bottom turn, peak maneuver), heavy
/// conditions (wave size, tube), and equipment mastery over raw time-in-water, so the
/// math itself acts as the safety gate against self-overrating. See `SkillScorer` for the
/// summing + bucketing into a `SkillLevel`.
struct SkillQuiz {
    enum Q: String, CaseIterable, Codable, Identifiable {
        case yearsSurfing
        case sessionFrequency
        case popUpConsistency
        case paddleEndurance
        case bottomTurn
        case cutback
        case peakManeuver
        case tubeRiding
        case biggestWave
        case waveReading
        case equipmentMastery

        var id: String { rawValue }

        var prompt: String {
            switch self {
            case .yearsSurfing: "How long have you been surfing?"
            case .sessionFrequency: "How often do you surf?"
            case .popUpConsistency: "How's your pop-up?"
            case .paddleEndurance: "How's your paddle endurance?"
            case .bottomTurn: "How's your bottom turn?"
            case .cutback: "How's your cutback?"
            case .peakManeuver: "What's your peak maneuver / style?"
            case .tubeRiding: "Honestly, how's your tube riding?"
            case .biggestWave: "Biggest wave you've surfed comfortably?"
            case .waveReading: "How well do you read a wave?"
            case .equipmentMastery: "How dialed is your equipment & quiver?"
            }
        }

        var options: [(String, Int)] {  // (label, points)
            switch self {
            case .yearsSurfing:
                return [("< 1 year", 0), ("1–3 years", 2), ("3–5 years", 3), ("5+ years", 5)]
            case .sessionFrequency:
                return [("A few times a year", 0), ("A few times a month", 2), ("Weekly", 4), ("Multiple times a week", 5)]
            case .popUpConsistency:
                return [("To the knees first", 0), ("Sometimes unstable on steep drops", 4), ("Reliable, but I have to look down", 7), ("Instant, blind, and right into my stance", 10)]
            case .paddleEndurance:
                return [("Exhausted after 30 mins", 0), ("Fine in average beach breaks", 5), ("Can paddle against a point break sweep without resting", 10)]
            case .bottomTurn:
                return [("I mostly angle on the drop", 3), ("Functional, gets me down the line", 8), ("Deep, compressed, and dictates my next maneuver", 15)]
            case .cutback:
                return [("I usually just kick out or lose the wave", 0), ("I can turn back, but often lose speed", 5), ("Full roundhouse, rebounding off the whitewash", 10)]
            case .peakManeuver:
                return [("None of the above yet", 0), ("A standard top turn / snap", 7), ("A heavy, displacing rail carve or layback", 15), ("Finding and navigating the barrel", 15), ("A clean aerial maneuver", 15)]
            case .tubeRiding:
                return [("I avoid the barrel", 0), ("I pull in constantly, but rarely make it out", 7), ("I can confidently pump and exit a clean tube", 10)]
            case .biggestWave:
                return [("Waist high", 0), ("Chest to Head high", 4), ("Overhead", 7), ("Double Overhead+", 10)]
            case .waveReading:
                return [("I just paddle and hope", 0), ("I can usually spot the peak", 5), ("I know exactly where a wave will pitch before it breaks", 10)]
            case .equipmentMastery:
                return [("I rent or just ride whatever board I have.", 0), ("I own a board I like, but I'm not totally sure of the exact dimensions or volume.", 4), ("I know my baseline volume and switch between a couple of boards depending on the size of the waves.", 7), ("I know my exact volume needs, have a dialed quiver, and adjust my board/fins for the specific spot and conditions.", 10)]
            }
        }
    }

    struct Answers: Codable, Equatable {
        var values: [String: Int] = [:]   // Q.rawValue → option index (0..n)

        func score(_ q: Q) -> Int {
            guard let idx = values[q.rawValue] else { return 0 }
            // option index → points (the second element of each tuple)
            let opts = q.options
            guard idx >= 0, idx < opts.count else { return 0 }
            return opts[idx].1
        }

        var isComplete: Bool { Q.allCases.allSatisfy { values[$0.rawValue] != nil } }
        var completedCount: Int { Q.allCases.filter { values[$0.rawValue] != nil }.count }
    }
}

/// Additive 110-point scorer. Sums the 11 quiz questions and buckets the total into a
/// `SkillLevel`. Purely additive — no safety gates; the point weighting is the gate.
struct SkillScorer {
    struct Result: Equatable {
        let total: Int
        let level: SkillLevel
    }

    /// Max attainable total across all 11 questions (110).
    static let maxScore = 110

    static func score(_ answers: SkillQuiz.Answers) -> Result {
        let total = SkillQuiz.Q.allCases.reduce(0) { $0 + answers.score($1) }
        let level: SkillLevel
        switch total {
        case ...25:   level = .beginner
        case 26...45: level = .novice
        case 46...75: level = .intermediate
        case 76...95: level = .advanced
        default:      level = .expert   // 96...110
        }
        return Result(total: total, level: level)
    }
}
