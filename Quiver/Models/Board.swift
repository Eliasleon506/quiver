import Foundation
import SwiftData

@Model
final class Board {
    @Attribute(.unique) var id: UUID
    var nickname: String?
    var type: BoardType
    var lengthIn: Double
    var widthIn: Double
    var thicknessIn: Double
    var volumeL: Double?
    var tailShape: TailShape?
    var notes: String?
    var addedAt: Date

    init(
        id: UUID = UUID(),
        nickname: String? = nil,
        type: BoardType,
        lengthIn: Double,
        widthIn: Double,
        thicknessIn: Double,
        volumeL: Double? = nil,
        tailShape: TailShape? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.type = type
        self.lengthIn = lengthIn
        self.widthIn = widthIn
        self.thicknessIn = thicknessIn
        self.volumeL = volumeL
        self.tailShape = tailShape
        self.notes = notes
        self.addedAt = Date()
    }

    /// User-entered volume if present, otherwise a geometric estimate from L×W×T × k.
    var effectiveVolumeL: Double {
        if let v = volumeL { return v }
        return lengthIn * widthIn * thicknessIn * type.shapeCoefficient * 0.01639
    }

    /// "5'10" formatted display of length.
    var lengthDisplay: String {
        let feet = Int(lengthIn) / 12
        let inches = lengthIn.truncatingRemainder(dividingBy: 12)
        if inches < 0.05 { return "\(feet)'" }
        let inchStr = inches == floor(inches)
            ? "\(Int(inches))"
            : String(format: "%.1f", inches)
        return "\(feet)'\(inchStr)\""
    }
}

// MARK: - Recommendation feedback (Phase 1)
//
// Appended here (not a new file) to avoid the xcodegen step. `RecFeedback` is a local-only
// thumbs-up/down + optional comment on a shown recommendation. Two uses: (1) reviewing whether
// Gemini's picks land vs. the old rules, and (2) the most recent few rows are fed back into future
// prompts as a soft "Surfer Preferences" summary. MUST be registered in the `ModelContainer` schema.

/// A point-in-time, decodable copy of what the recommendation card showed — stored as JSON in
/// `RecFeedback.recSnapshot` so a verdict stays interpretable later.
struct RecSnapshot: Codable, Sendable {
    var boardType: String
    var lengthIn: Double
    var widthIn: Double
    var thicknessIn: Double
    var volumeL: Double
    var conditionsSummary: String
    var wasAIGenerated: Bool

    /// "Shortboard 6'0" 19.25 × 2.50 ≈ 32.0 L" — used in the prompt's preferences summary.
    var boardLine: String {
        let display = BoardType(rawValue: boardType)?.displayName ?? boardType
        let ft = Int(lengthIn) / 12
        let inch = Int(lengthIn) % 12
        return String(format: "%@ %d'%d\" %.2f × %.2f ≈ %.1f L",
                      display, ft, inch, widthIn, thicknessIn, volumeL)
    }
}

@Model
final class RecFeedback {
    @Attribute(.unique) var id: UUID
    var spotId: String
    var createdAt: Date
    var ratingUp: Bool
    var comment: String?
    /// JSON of a `RecSnapshot` (what was shown when the verdict was given).
    var recSnapshot: Data
    /// Which engine produced the rated rec, so we can compare Gemini vs. the rule fallback.
    var wasAIGenerated: Bool

    init(
        id: UUID = UUID(),
        spotId: String,
        ratingUp: Bool,
        comment: String? = nil,
        snapshot: RecSnapshot,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.spotId = spotId
        self.ratingUp = ratingUp
        self.comment = comment
        self.recSnapshot = (try? JSONEncoder().encode(snapshot)) ?? Data()
        self.wasAIGenerated = snapshot.wasAIGenerated
        self.createdAt = createdAt
    }

    var decodedSnapshot: RecSnapshot? {
        try? JSONDecoder().decode(RecSnapshot.self, from: recSnapshot)
    }

    /// Builds the soft "Surfer Preferences" summary fed into future prompts. Most recent first,
    /// capped (default 5) to avoid over-anchoring on one-off comments.
    static func preferenceSummary(from rows: [RecFeedback], limit: Int = 5) -> [String] {
        rows.sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { row in
                let verdict = row.ratingUp ? "liked" : "disliked"
                let board = row.decodedSnapshot?.boardLine ?? "a recommendation"
                if let c = row.comment, !c.trimmingCharacters(in: .whitespaces).isEmpty {
                    return "User \(verdict) \(board) — noted: \"\(c)\""
                }
                return "User \(verdict) \(board)."
            }
    }
}
