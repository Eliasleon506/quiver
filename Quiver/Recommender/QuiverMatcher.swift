import Foundation

struct QuiverMatcher: Sendable {
    /// Returns up to 2 best matches from the quiver for the recommended type/volume.
    func match(
        quiver: [Board],
        type: BoardType,
        adjacent: [BoardType],
        targetVolume: VolumeRange
    ) -> [QuiverMatch] {
        guard !quiver.isEmpty else { return [] }
        let primaryAndAdjacent = Set([type] + adjacent + type.adjacent)
        let candidates = quiver.filter { primaryAndAdjacent.contains($0.type) }
        let pool = candidates.isEmpty ? quiver : candidates

        let scored: [QuiverMatch] = pool.map { board in
            let dist = abs(board.effectiveVolumeL - targetVolume.midpointL)
            let typeBonus = (board.type == type) ? 0.0 : 1.5
            let outOfRangePenalty = (board.effectiveVolumeL < targetVolume.lowL - 1
                                    || board.effectiveVolumeL > targetVolume.highL + 1) ? 1.0 : 0.0
            let score = dist + typeBonus + outOfRangePenalty
            return QuiverMatch(board: board, score: score, rationale: rationale(for: board, type: type, target: targetVolume))
        }
        return scored.sorted(by: { $0.score < $1.score }).prefix(2).map { $0 }
    }

    private func rationale(for board: Board, type: BoardType, target: VolumeRange) -> String {
        let name = board.nickname ?? board.type.displayName
        let inRange = (board.effectiveVolumeL >= target.lowL && board.effectiveVolumeL <= target.highL)
        let typeMatch = board.type == type
        let volStr = String(format: "%.1f L", board.effectiveVolumeL)
        switch (typeMatch, inRange) {
        case (true, true):
            return "Your \(board.lengthDisplay) \(name) at \(volStr) is right in the pocket."
        case (true, false):
            return "Your \(board.lengthDisplay) \(name) (\(volStr)) is the right type — just outside the volume window."
        case (false, true):
            return "Your \(board.lengthDisplay) \(name) (\(volStr)) — volume is right; closest type you've got."
        case (false, false):
            return "Closest match in your quiver: your \(board.lengthDisplay) \(name) at \(volStr)."
        }
    }
}
