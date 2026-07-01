import SwiftUI
import SwiftData

/// Forecast-verification dashboard: how close the app's Open-Meteo predictions landed to the live
/// NDBC buoy actuals, per spot. Surf forecasting is about *measurable* skill, so the app measures
/// its own — predictions are logged as you browse, then graded once each forecast hour arrives.
struct ForecastAccuracyView: View {
    let spotsStore: SpotsStore

    @Query private var records: [ForecastRecord]
    @Environment(\.dismiss) private var dismiss

    private var overall: ForecastAccuracy.Summary { ForecastAccuracy.summarize(records) }
    private var perSpot: [(spotId: String, summary: ForecastAccuracy.Summary)] {
        ForecastAccuracy.bySpot(records)
    }
    private var pendingCount: Int { records.filter { !$0.isResolved }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if overall.sampleCount == 0 {
                        ContentUnavailableView(
                            "No verified forecasts yet",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Predictions are logged as you browse spots, then checked against live buoy readings once that hour arrives. Check back after the app has run across a few tide cycles.")
                        )
                    } else {
                        statRow("Mean error (wave height)",
                                String(format: "%.1f ft", overall.waveHeightMAEft))
                        statRow("Bias",
                                String(format: "%+.1f ft", overall.waveHeightBiasFt),
                                hint: overall.waveHeightBiasFt >= 0 ? "tends to over-forecast"
                                                                    : "tends to under-forecast")
                        if overall.periodSampleCount > 0 {
                            statRow("Mean error (period)",
                                    String(format: "%.1f s", overall.periodMAEs))
                        }
                        statRow("Verified samples", "\(overall.sampleCount)")
                    }
                } header: {
                    Text("Forecast accuracy")
                } footer: {
                    Text("\(overall.sampleCount) verified · \(pendingCount) awaiting their forecast hour. Predictions: Open-Meteo. Actuals: NOAA NDBC buoys.")
                }

                if !perSpot.isEmpty {
                    Section("By spot") {
                        ForEach(perSpot, id: \.spotId) { row in
                            HStack {
                                Text(spotName(row.spotId))
                                Spacer()
                                Text(String(format: "%.1f ft", row.summary.waveHeightMAEft))
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text("n=\(row.summary.sampleCount)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Forecast Accuracy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func spotName(_ id: String) -> String {
        spotsStore.spot(id: id)?.name ?? id
    }

    @ViewBuilder
    private func statRow(_ label: String, _ value: String, hint: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
        }
    }
}
