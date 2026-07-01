import Foundation

/// Given a target volume + board type + skill + surfer height, produce a *physically sane* L × W × T.
/// Uses `V ≈ L × W × T × k × 0.01639` (inches → liters), then clamps length to height/type bounds and
/// rebalances width·thickness so the final dims still hit the target volume — like a real shaper would.
struct DimensionBuilder: Sendable {
    private let cubicInchToLiter = 0.01639

    func suggest(
        type: BoardType,
        skill: SkillLevel,
        targetVolume: VolumeRange,
        userHeightIn: Double,
        userWeightLb: Double
    ) -> DimensionSuggestion {
        // Longboards are float-first: a skilled surfer on a tiny day still gets a real 8'6"+ plank,
        // not a 15"-wide longboard squeezed down to a shortboard volume target. Physical dims drive
        // the volume here, not the other way around.
        if type == .longboard {
            return longboardSuggestion(weightLb: userWeightLb)
        }

        let k = type.shapeCoefficient
        // Mid-lengths / funboards are float machines — let the target breathe up 20% before solving,
        // and they get a hard width/thickness floor below (no skinny mid-lengths).
        let isMidLengthFamily = (type == .midLength || type == .funboard)
        let targetL = targetVolume.midpointL * (isMidLengthFamily ? 1.20 : 1.0)
        var (width, thickness) = baseWidthThickness(type: type, skill: skill)

        // 1. Raw length from target volume at the base width/thickness.
        let rawLength = targetL / (width * thickness * k * cubicInchToLiter)

        // 2. Clamp length to a physically sane window for this type + surfer height.
        let (lMin, lMax) = lengthClamp(type: type, heightIn: userHeightIn)
        let clampedLength = min(max(rawLength, lMin), lMax)

        // 3. If length was forced, rebalance W·T (keeping their ratio) to preserve target volume.
        if abs(clampedLength - rawLength) > 0.001 {
            let neededWT = targetL / (clampedLength * k * cubicInchToLiter)
            let scale = (neededWT / (width * thickness)).squareRoot()
            width *= scale
            thickness *= scale
        }

        // 4. Absolute width/thickness safety clamps (a board can't be paper-thin or a plank).
        (width, thickness) = safetyClamp(type: type, width: width, thickness: thickness)

        // 5. Snap to real-world increments and recompute the volume actually achieved.
        let snappedLength = (clampedLength * 2).rounded() / 2          // ½"
        let snappedWidth = (width * 8).rounded() / 8                   // ⅛"
        let snappedThickness = (thickness * 16).rounded() / 16         // 1/16"
        let resolvedVolume = snappedLength * snappedWidth * snappedThickness * k * cubicInchToLiter

        return DimensionSuggestion(
            type: type,
            lengthIn: snappedLength,
            widthIn: snappedWidth,
            thicknessIn: snappedThickness,
            volumeL: resolvedVolume
        )
    }

    /// Gemini-driven sizing: solve a physically sane L × W × T that hits the model's **exact**
    /// requested volume. Starts from Gemini's optional `dimPreferences` (aesthetic intent) or the
    /// type's skill defaults, clamps length to the type/height window, then nudges width·thickness
    /// (preserving their ratio) so the board mathematically lands on `targetVolumeL` — finally
    /// applying the same hard physical safety clamps + real-world snap as `suggest(...)`.
    ///
    /// Unlike `suggest(...)`, this does NOT apply the legacy mid-length +20% breathing room or the
    /// longboard weight-locked path: Gemini owns the volume, so we honor it directly for every type.
    func suggestForTargetVolume(
        type: BoardType,
        skill: SkillLevel,
        targetVolumeL: Double,
        userHeightIn: Double,
        preferredLengthIn: Double? = nil,
        preferredWidthIn: Double? = nil,
        preferredThicknessIn: Double? = nil
    ) -> DimensionSuggestion {
        let k = type.shapeCoefficient
        let targetL = max(targetVolumeL, 1.0)   // guard against a zero/garbage target
        let (baseW, baseT) = baseWidthThickness(type: type, skill: skill)
        var width = preferredWidthIn ?? baseW
        var thickness = preferredThicknessIn ?? baseT

        // 1. Length: honor Gemini's preference if given, else solve from volume at base W/T.
        let rawLength = preferredLengthIn ?? (targetL / (width * thickness * k * cubicInchToLiter))

        // 2. Clamp length to a physically sane window for this type + surfer height.
        let (lMin, lMax) = lengthClamp(type: type, heightIn: userHeightIn)
        let clampedLength = min(max(rawLength, lMin), lMax)

        // 3. Rebalance W·T (keeping their ratio) so the final dims hit the EXACT target volume.
        let neededWT = targetL / (clampedLength * k * cubicInchToLiter)
        let scale = (neededWT / (width * thickness)).squareRoot()
        width *= scale
        thickness *= scale

        // 4. Absolute width/thickness safety clamps (a board can't be paper-thin or a plank).
        (width, thickness) = safetyClamp(type: type, width: width, thickness: thickness)

        // 5. Snap to real-world increments and recompute the volume actually achieved.
        let snappedLength = (clampedLength * 2).rounded() / 2          // ½"
        let snappedWidth = (width * 8).rounded() / 8                   // ⅛"
        let snappedThickness = (thickness * 16).rounded() / 16         // 1/16"
        let resolvedVolume = snappedLength * snappedWidth * snappedThickness * k * cubicInchToLiter

        return DimensionSuggestion(
            type: type,
            lengthIn: snappedLength,
            widthIn: snappedWidth,
            thicknessIn: snappedThickness,
            volumeL: resolvedVolume
        )
    }

    /// Longboard dims from weight, not volume. Length steps by weight; width/thickness locked to a
    /// real plank range so volume falls out naturally (safely 60 L+).
    private func longboardSuggestion(weightLb: Double) -> DimensionSuggestion {
        let length: Double
        switch weightLb {
        case ..<150:    length = 102   // 8'6"
        case 150...190: length = 108   // 9'0"
        default:        length = 114   // 9'6"
        }
        let width = 22.5      // locked 22.0–23.0
        let thickness = 3.0   // locked 2.75–3.25
        let k = BoardType.longboard.shapeCoefficient
        let volume = length * width * thickness * k * cubicInchToLiter
        return DimensionSuggestion(
            type: .longboard, lengthIn: length, widthIn: width, thicknessIn: thickness, volumeL: volume
        )
    }

    /// Skill-scaled base width/thickness. Performance widths order hpsb < shortboard < allRounder.
    private func baseWidthThickness(type: BoardType, skill: SkillLevel) -> (Double, Double) {
        switch type {
        case .hpsb:
            switch skill {
            case .beginner, .novice, .intermediate: return (19.0, 2.45)
            case .advanced: return (18.75, 2.40)
            case .expert: return (18.5, 2.35)
            }
        case .shortboard:
            switch skill {
            case .beginner, .novice, .intermediate: return (19.5, 2.55)
            case .advanced: return (19.25, 2.50)
            case .expert: return (19.0, 2.45)
            }
        case .allRounder:
            switch skill {
            case .beginner, .novice, .intermediate: return (20.0, 2.60)
            case .advanced: return (19.75, 2.55)
            case .expert: return (19.5, 2.50)
            }
        case .groveler, .fish: return (20.5, 2.55)
        case .stepUp:          return (19.0, 2.50)
        case .midLength, .funboard: return (21.5, 2.75)
        case .longboard:       return (22.5, 3.0)
        case .gun:             return (18.75, 2.55)
        }
    }

    /// Physically sane length window (inches) per board type, relative to surfer height `H`.
    private func lengthClamp(type: BoardType, heightIn h: Double) -> (Double, Double) {
        switch type {
        case .hpsb:             return (min(h - 2, 64), h + 4)
        case .shortboard:       return (min(h - 4, 62), h + 2)
        case .allRounder:       return (min(h - 6, 60), h)
        case .groveler, .fish:
            // Hard 5'2" floor — grovelers/fish ride short, but never stubbier than 62" regardless
            // of how short the surfer is (clamped to the upper bound so the window can't invert).
            let upper = h + 1
            return (min(62, upper), upper)
        case .stepUp:           return (h + 2, h + 8)
        case .midLength, .funboard: return (80, 102)   // 6'8"–8'6"
        case .longboard:        return (102, 120)      // 8'6"–10'0"
        case .gun:              return (h + 12, 126)    // …–10'6"
        }
    }

    /// Absolute safety bounds for a standard adult board.
    private func safetyClamp(type: BoardType, width: Double, thickness: Double) -> (Double, Double) {
        var w = width
        var t = thickness
        // Thickness: never paper-thin, never a plank (longboards may run thicker).
        let tMax = (type == .longboard) ? 4.0 : 3.5
        t = min(max(t, 2.15), tMax)
        // Type-aware width windows + the float-board thickness floor.
        switch type {
        case .hpsb, .shortboard, .allRounder, .stepUp:
            w = min(max(w, 18.25), 21.0)
        case .midLength, .funboard:
            w = min(max(w, 20.5), 22.5)   // never a skinny mid-length
            t = max(t, 2.5)               // and never paper-thin
        case .groveler, .fish:
            w = min(max(w, 19.5), 22.0)   // wide planshape, but not a runaway barge when sized short
        default:
            break
        }
        return (w, t)
    }
}
