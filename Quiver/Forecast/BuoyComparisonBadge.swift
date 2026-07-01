import SwiftUI

/// Compares the model-forecast swell against the latest live NDBC buoy observation
/// to ground-truth the recommendation. Renders nothing if there's no live buoy data.
struct BuoyComparisonBadge: View {
    let snapshot: ConditionsSnapshot
    let buoyId: String?

    var body: some View {
        if let buoyFt = buoyHeightFt {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Live buoy")
                            .font(.caption.weight(.semibold))
                        if let id = buoyId {
                            Text("#\(id)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(comparisonText(buoyFt: buoyFt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f ft", buoyFt))
                    .font(.body.weight(.semibold).monospacedDigit())
                if let period = snapshot.buoyDominantPeriodS {
                    Text(String(format: "@ %.0fs", period))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var buoyHeightFt: Double? {
        snapshot.buoyWaveHeightM.map { $0 * 3.28084 }
    }

    private func comparisonText(buoyFt: Double) -> String {
        guard let forecastFt = snapshot.primarySwellHeightFt else {
            return "Latest open-ocean observation."
        }
        let delta = buoyFt - forecastFt
        if abs(delta) < 0.5 {
            return "Matches the forecast — solid confidence."
        } else if delta > 0 {
            return String(format: "Running %.1f ft bigger than forecast.", delta)
        } else {
            return String(format: "Running %.1f ft smaller than forecast.", abs(delta))
        }
    }
}
