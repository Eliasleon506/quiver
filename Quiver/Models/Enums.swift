import Foundation

enum SkillLevel: String, Codable, CaseIterable, Identifiable {
    case beginner, novice, intermediate, advanced, expert

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: "Beginner"
        case .novice: "Novice"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        case .expert: "Expert / Pro"
        }
    }

    /// Firewire-style range of bodyweight multipliers.
    var multiplierRange: ClosedRange<Double> {
        switch self {
        case .beginner: 0.85...1.00
        case .novice: 0.65...0.80
        case .intermediate: 0.45...0.55
        case .advanced: 0.38...0.42
        case .expert: 0.34...0.38
        }
    }
}

enum Gender: String, Codable, CaseIterable, Identifiable {
    case male, female, other, preferNotToSay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        case .preferNotToSay: "Prefer not to say"
        }
    }
}

enum BoardType: String, Codable, CaseIterable, Identifiable {
    case hpsb, shortboard, allRounder, groveler, fish, midLength, longboard, stepUp, gun, funboard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hpsb: "HPSB (Pro Blade)"
        case .shortboard: "Shortboard (Daily Driver)"
        case .allRounder: "All-Rounder (Hybrid)"
        case .groveler: "Groveler"
        case .fish: "Fish"
        case .midLength: "Mid-length"
        case .longboard: "Longboard"
        case .stepUp: "Step-up"
        case .gun: "Gun"
        case .funboard: "Funboard"
        }
    }

    /// Shape coefficient `k` in `V ≈ L × W × T × k` (with L, W, T in inches → result in liters).
    /// Single source of `k`, consumed by both `Board.effectiveVolumeL` and `DimensionBuilder`.
    /// Lower `k` = more rocker / foiled rails (less volume per box); higher `k` = flatter & fuller.
    var shapeCoefficient: Double {
        switch self {
        case .hpsb: 0.565        // highly rockered, foiled rails, narrow
        case .shortboard: 0.585  // daily driver, moderate rocker, slightly fuller
        case .allRounder: 0.605  // hybrid, wider point forward, flatter rocker
        case .stepUp: 0.58
        case .gun: 0.540
        case .groveler: 0.635
        case .fish: 0.635
        case .midLength: 0.675
        case .funboard: 0.675
        case .longboard: 0.725
        }
    }

    /// Adjacent types — used when matching the quiver.
    var adjacent: [BoardType] {
        switch self {
        case .hpsb: [.shortboard, .stepUp]
        case .shortboard: [.hpsb, .allRounder]
        case .allRounder: [.shortboard, .groveler]
        case .groveler: [.allRounder, .fish]
        case .fish: [.groveler, .midLength]
        case .midLength: [.fish, .funboard, .longboard]
        case .funboard: [.midLength, .longboard]
        case .longboard: [.funboard, .midLength]
        case .stepUp: [.hpsb, .shortboard, .gun]
        case .gun: [.stepUp]
        }
    }

    /// One step toward forgiveness / float. Used by `.softAndSlow` wave character and tide-swamp.
    func downgradeTier() -> BoardType {
        switch self {
        case .gun: .stepUp
        case .stepUp: .hpsb
        case .hpsb: .shortboard
        case .shortboard: .allRounder
        case .allRounder: .midLength
        case .groveler: .midLength
        case .fish: .midLength
        case .funboard: .longboard
        case .midLength: .longboard
        case .longboard: .longboard   // floor
        }
    }

    /// One step toward performance / hold. Used by `.heavyHollow` wave character.
    /// `.hpsb` / `.shortboard` hold — they are already the performance picks on heavy waves.
    func upgradeTier() -> BoardType {
        switch self {
        case .allRounder: .shortboard
        case .groveler: .allRounder
        case .fish: .allRounder
        case .midLength: .allRounder
        case .funboard: .midLength
        case .longboard: .funboard
        case .hpsb, .shortboard, .stepUp, .gun: self  // hold
        }
    }
}

enum SpotRegion: String, Codable, CaseIterable, Identifiable {
    // Declaration order drives the Spot Picker section order (see SpotsStore.grouped):
    // north-to-south down California, then international at the bottom.
    case centralCoast = "CentralCoast"
    case sbNorth = "SBNorth"
    case sbSouth = "SBSouth"
    case venturaCounty = "VenturaCounty"
    case costaRicaCentralPacific = "CostaRicaCentralPacific"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .centralCoast: "Central Coast"
        case .sbNorth: "Goleta / SB North"
        case .sbSouth: "Santa Barbara"
        case .venturaCounty: "Ventura County"
        case .costaRicaCentralPacific: "Costa Rica — Central Pacific"
        }
    }
}

enum TideTrend: String, Codable {
    case rising, falling, slack
}

/// How a spot breaks — drives the wave-character override step in the recommender.
enum WaveCharacter: String, Codable, CaseIterable, Identifiable {
    case softAndSlow      // mushy, forgiving coves/beachies — no HPSBs here
    case performancePoint // clean, rippable points — ride the baseline
    case heavyHollow      // powerful / hollow — flat rockers dig the nose

    var id: String { rawValue }
}

/// The tide band a spot prefers — drives the tide-swamp gate.
enum TidePreference: String, Codable, CaseIterable, Identifiable {
    case lowToMid   // drains out / gets fat on a high tide
    case midToHigh
    case allTides

    var id: String { rawValue }
}

enum TailShape: String, Codable, CaseIterable, Identifiable {
    case squash, round, swallow, pin, square, diamond

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

/// Wetsuit tiers we reason about (Phase 2). Trunks = "no suit" is represented as `nil`, not a case.
/// `warmthRank` orders them coldest-capable last, so `WetsuitSelector` can find the closest owned
/// suit to the temp-derived ideal and compute a wet-weight penalty.
enum Wetsuit: String, Codable, CaseIterable, Identifiable {
    case springSuit
    case threeTwo
    case fourThree
    case fourThreeHoodBooties

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .springSuit: "Spring suit"
        case .threeTwo: "3/2 full"
        case .fourThree: "4/3 full"
        case .fourThreeHoodBooties: "4/3 + hood & booties"
        }
    }

    /// Higher = warmer / more rubber. Used to find the closest owned suit to the ideal.
    var warmthRank: Int {
        switch self {
        case .springSuit: 1
        case .threeTwo: 2
        case .fourThree: 3
        case .fourThreeHoodBooties: 4
        }
    }

    /// Extra "wet weight" (lb) added to effective body weight — more rubber floats more and paddles
    /// heavier. First-pass ladder (tunable): spring +1, 3/2 +3, 4/3 +5, 4/3+hood/booties +8.
    var wetWeightPenaltyLb: Double {
        switch self {
        case .springSuit: 1
        case .threeTwo: 3
        case .fourThree: 5
        case .fourThreeHoodBooties: 8
        }
    }

    /// Performance implications fed into the Gemini prompt as subjective context.
    var performanceNote: String {
        switch self {
        case .springSuit: "light rubber — minimal float or mobility impact."
        case .threeTwo: "moderate rubber — a little extra float and slightly stiffer shoulders."
        case .fourThree: "thick rubber — noticeable extra float, paddle weight, and reduced shoulder mobility."
        case .fourThreeHoodBooties: "heavy rubber + hood/booties — significant float and paddle weight, cold fatigue, and limited mobility."
        }
    }
}
