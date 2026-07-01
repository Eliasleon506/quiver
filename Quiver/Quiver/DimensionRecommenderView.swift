import SwiftUI
import SwiftData

/// "If you bought a board for these conditions, get something like X."
/// Pre-fills from the user's profile + a conditions preset; type can be overridden.
struct DimensionRecommenderView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    @State private var preset: ConditionsPreset = .average
    @State private var skillOverride: SkillLevel?
    @State private var typeOverride: BoardType?

    private let volumeCalculator = VolumeCalculator()
    private let dimensionBuilder = DimensionBuilder()
    private let typeSelector = BoardTypeSelector()

    var body: some View {
        Form {
            Section("Conditions") {
                Picker("Preset", selection: $preset) {
                    ForEach(ConditionsPreset.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                Text(preset.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("You") {
                Picker("Skill", selection: $skillOverride) {
                    Text("From profile").tag(SkillLevel?.none)
                    ForEach(SkillLevel.allCases) { s in
                        Text(s.displayName).tag(SkillLevel?.some(s))
                    }
                }
                if let p = profiles.first {
                    LabeledContent("Weight", value: "\(Int(p.weightLb)) lb")
                    LabeledContent("Age", value: "\(p.age)")
                }
            }

            Section("Board type") {
                Picker("Type", selection: $typeOverride) {
                    Text("Auto-pick (\(autoPickType?.displayName ?? "—"))").tag(BoardType?.none)
                    ForEach(BoardType.allCases) { t in
                        Text(t.displayName).tag(BoardType?.some(t))
                    }
                }
            }

            if let result = computeResult() {
                Section("Suggested dimensions") {
                    LabeledContent("Length") {
                        Text(formatLength(result.suggestion.lengthIn))
                            .font(.body.monospacedDigit())
                    }
                    LabeledContent("Width") {
                        Text(String(format: "%.3f\"", result.suggestion.widthIn))
                            .font(.body.monospacedDigit())
                    }
                    LabeledContent("Thickness") {
                        Text(String(format: "%.2f\"", result.suggestion.thicknessIn))
                            .font(.body.monospacedDigit())
                    }
                    LabeledContent("Volume") {
                        Text(String(format: "%.1f L", result.suggestion.volumeL))
                            .font(.body.monospacedDigit())
                    }
                }
                Section {
                    Text("Target volume range: \(result.volume.formatted())")
                        .font(.callout)
                } footer: {
                    Text("V ≈ L × W × T × \(String(format: "%.3f", result.suggestion.type.shapeCoefficient)) × 0.01639 (in → L)")
                        .font(.caption)
                }
            } else {
                Section {
                    Text("Complete onboarding to see suggested dimensions.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sizing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var resolvedSkill: SkillLevel? {
        skillOverride ?? profiles.first?.skillLevel
    }

    private var autoPickType: BoardType? {
        guard let profile = profiles.first else { return nil }
        let snap = preset.snapshot(spotId: "synthetic")
        return typeSelector.choose(
            conditions: snap,
            spot: Self.syntheticSpot,
            skill: skillOverride ?? profile.skillLevel
        ).primary
    }

    private struct ComputedResult {
        let suggestion: DimensionSuggestion
        let volume: VolumeRange
    }

    private func computeResult() -> ComputedResult? {
        guard let profile = profiles.first else { return nil }
        let skill = skillOverride ?? profile.skillLevel
        let snap = preset.snapshot(spotId: "synthetic")
        let spot = Self.syntheticSpot
        let advisoryHit = BlownOutAdvisor().evaluate(conditions: snap, spot: spot)
        let autoType = typeSelector.choose(conditions: snap, spot: spot, skill: skill).primary
        let type = typeOverride ?? autoType
        let volume = volumeCalculator.targetVolume(
            weightKg: profile.weightKg,
            skill: skill,
            age: profile.age,
            conditions: snap,
            advisory: advisoryHit
        )
        let suggestion = dimensionBuilder.suggest(
            type: type, skill: skill, targetVolume: volume,
            userHeightIn: profile.heightIn, userWeightLb: profile.weightLb
        )
        return ComputedResult(suggestion: suggestion, volume: volume)
    }

    private func formatLength(_ inches: Double) -> String {
        let feet = Int(inches) / 12
        let rem = inches.truncatingRemainder(dividingBy: 12)
        let inchStr = rem == floor(rem) ? "\(Int(rem))" : String(format: "%.1f", rem)
        return "\(feet)'\(inchStr)\""
    }

    private static let syntheticSpot = Spot(
        id: "synthetic", name: "Synthetic",
        lat: 34.4, lon: -119.7, region: .sbSouth,
        ndbcBuoyId: nil, tideStationId: nil,
        optimalSwellDirMinDeg: 200, optimalSwellDirMaxDeg: 290,
        favorableWindDirMinDeg: 0, favorableWindDirMaxDeg: 90,
        notes: nil
    )
}

/// Preset condition profiles for the standalone dimension recommender.
enum ConditionsPreset: String, CaseIterable, Identifiable {
    case small, average, solid, big
    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: "Small"
        case .average: "Average"
        case .solid: "Solid"
        case .big: "Big"
        }
    }

    var description: String {
        switch self {
        case .small: "Knee-to-waist high, weak — 1.5 ft @ 8s"
        case .average: "Chest-to-shoulder, clean — 3.5 ft @ 11s"
        case .solid: "Head-high+, organized — 6 ft @ 13s"
        case .big: "Overhead+, powerful — 9 ft @ 15s"
        }
    }

    func snapshot(spotId: String) -> ConditionsSnapshot {
        let heightFt: Double
        let period: Double
        switch self {
        case .small: heightFt = 1.5; period = 8
        case .average: heightFt = 3.5; period = 11
        case .solid: heightFt = 6.0; period = 13
        case .big: heightFt = 9.0; period = 15
        }
        return ConditionsSnapshot(
            spotId: spotId,
            timestamp: Date(), fetchedAt: Date(),
            swellHeightM: heightFt / 3.28084,
            swellPeriodS: period,
            swellDirDeg: 270,
            waveHeightM: nil, wavePeriodS: nil, waveDirDeg: nil,
            windSpeedKt: 5, windDirDeg: 45, windGustKt: nil,
            tideHeightM: nil, tideTrend: nil,
            buoyWaveHeightM: nil, buoyDominantPeriodS: nil, buoyMeanDirDeg: nil
        )
    }
}
