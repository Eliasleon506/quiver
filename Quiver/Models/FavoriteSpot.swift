import Foundation
import SwiftData

/// A user-favorited spot. Spots themselves are seeded read-only from JSON, so we only
/// persist the stable slug here. Migrates cleanly to CloudKit later (Phase 5).
@Model
final class FavoriteSpot {
    @Attribute(.unique) var spotId: String
    var addedAt: Date

    init(spotId: String) {
        self.spotId = spotId
        self.addedAt = Date()
    }
}
