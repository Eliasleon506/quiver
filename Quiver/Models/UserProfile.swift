import Foundation
import SwiftData

@Model
final class UserProfile {
    var heightIn: Double
    var weightLb: Double
    var age: Int
    var gender: Gender
    var skillLevel: SkillLevel
    var quizAnswers: Data?
    var createdAt: Date
    var updatedAt: Date

    // Owned rubber (Phase 2). Defaulted so existing SwiftData stores migrate lightweight, with no
    // init-parameter change. `hasHoodBooties` is an add-on to the 4/3, not a standalone suit.
    var hasSpringSuit: Bool = false
    var has32: Bool = false
    var has43: Bool = false
    var hasHoodBooties: Bool = false

    init(
        heightIn: Double,
        weightLb: Double,
        age: Int,
        gender: Gender,
        skillLevel: SkillLevel,
        quizAnswers: Data? = nil
    ) {
        self.heightIn = heightIn
        self.weightLb = weightLb
        self.age = age
        self.gender = gender
        self.skillLevel = skillLevel
        self.quizAnswers = quizAnswers
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var weightKg: Double { weightLb * 0.45359237 }
    var heightCm: Double { heightIn * 2.54 }
}
