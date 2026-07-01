import SwiftUI
import SwiftData
import Charts

struct ForecastView: View {
    let spot: Spot

    @Query private var profiles: [UserProfile]

    @Query(sort: \RecFeedback.createdAt, order: .reverse) private var feedback: [RecFeedback]

    @State private var snapshots: [ConditionsSnapshot] = []
    @State private var bestWindow: ForecastQuality.Window?
    @State private var dailyVolumes: [ForecastVolume.DailyMin] = []
    @State private var loading = true
    @State private var error: String?

    private let provider: ConditionsProvider = CompositeConditionsProvider.shared
    private let gemini = GeminiRecommender()
    private let forecastHours = 168  // 7 days

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if loading {
                    ProgressView("Loading 7-day forecast…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 60)
                } else if let error {
                    errorCard(error)
                } else if snapshots.isEmpty {
                    Text("No forecast data available.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    if let window = bestWindow {
                        bestWindowCard(window)
                    }
                    minVolumeSection
                    swellChart
                    windChart
                    tideChart
                }
            }
            .padding()
        }
        .navigationTitle("7-day forecast")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Best window

    private func bestWindowCard(_ window: ForecastQuality.Window) -> some View {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE h a"
        let startFmt = DateFormatter()
        startFmt.dateFormat = "h a"
        let range = "\(startFmt.string(from: window.start))–\(startFmt.string(from: window.end))"

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text("Best window today").font(.headline)
            }
            Text("\(range) · \(ForecastQuality.label(forScore: window.peakScore)) "
                 + "(\(Int(window.peakScore * 100))%)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Minimum recommended volume (per day)

    @ViewBuilder
    private var minVolumeSection: some View {
        let rows = dailyVolumes
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recommended volume").font(.headline)
                    Text("L").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        Text(weekday(row.date))
                            .font(.body.weight(.medium))
                            .frame(width: 42, alignment: .leading)
                        Text(conditionsBlurb(row))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(row.range.formatted())
                            .font(.body.weight(.semibold).monospacedDigit())
                    }
                }
                Text("Target volume range for each day's conditions and your profile. The low end is the smallest board you'd want; size up toward the high end for comfort.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func weekday(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return fmt.string(from: date)
    }

    private func conditionsBlurb(_ row: ForecastVolume.DailyMin) -> String {
        let ft = row.swellFt.map { String(format: "%.1f ft", $0) } ?? "—"
        let period = row.periodS.map { String(format: "%.0fs", $0) } ?? "—"
        return "\(ft) @ \(period)"
    }

    // MARK: - Charts

    private var swellChart: some View {
        chartSection(title: "Swell", unit: "ft") {
            Chart {
                ForEach(swellPoints, id: \.time) { p in
                    AreaMark(
                        x: .value("Time", p.time),
                        y: .value("Height (ft)", p.value)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue.opacity(0.5), .blue.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Time", p.time),
                        y: .value("Height (ft)", p.value)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
                }
                bestWindowMark
            }
            .chartXAxis { dayAxis }
            .frame(height: 180)
        }
    }

    private var windChart: some View {
        chartSection(title: "Wind", unit: "kt") {
            Chart {
                ForEach(windPoints, id: \.time) { p in
                    LineMark(
                        x: .value("Time", p.time),
                        y: .value("Wind (kt)", p.value)
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.monotone)
                }
                bestWindowMark
            }
            .chartXAxis { dayAxis }
            .frame(height: 140)
        }
    }

    private var tideChart: some View {
        chartSection(title: "Tide", unit: "ft") {
            Chart {
                ForEach(tidePoints, id: \.time) { p in
                    LineMark(
                        x: .value("Time", p.time),
                        y: .value("Tide (ft)", p.value)
                    )
                    .foregroundStyle(.teal)
                    .interpolationMethod(.catmullRom)
                }
                bestWindowMark
            }
            .chartXAxis { dayAxis }
            .frame(height: 140)
        }
    }

    @ChartContentBuilder
    private var bestWindowMark: some ChartContent {
        if let window = bestWindow {
            RectangleMark(
                xStart: .value("Start", window.start),
                xEnd: .value("End", window.end)
            )
            .foregroundStyle(.yellow.opacity(0.18))
        }
    }

    private var dayAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day)) { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
        }
    }

    private func chartSection<Content: View>(
        title: String, unit: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data shaping

    private struct Point { let time: Date; let value: Double }

    private var swellPoints: [Point] {
        snapshots.compactMap { s in
            s.primarySwellHeightFt.map { Point(time: s.timestamp, value: $0) }
        }
    }

    private var windPoints: [Point] {
        snapshots.compactMap { s in
            s.windSpeedKt.map { Point(time: s.timestamp, value: $0) }
        }
    }

    private var tidePoints: [Point] {
        snapshots.compactMap { s in
            s.tideHeightM.map { Point(time: s.timestamp, value: $0 * 3.28084) }
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Couldn't load forecast").font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary)
            Button("Retry") { Task { await load() } }
                .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    @MainActor
    private func load() async {
        loading = true
        error = nil
        do {
            let result = try await provider.forecast(spot: spot, hours: forecastHours)
            self.snapshots = result
            self.bestWindow = ForecastQuality.bestWindowToday(result, spot: spot)
            if let profile = profiles.first {
                self.dailyVolumes = await dailyVolumes(for: profile, snapshots: result)
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// Gemini-powered 7-day volumes via ONE batched call, with the rule `ForecastVolume` as the
    /// offline/safety fallback for the whole array.
    @MainActor
    private func dailyVolumes(for profile: UserProfile, snapshots: [ConditionsSnapshot]) async -> [ForecastVolume.DailyMin] {
        let baseline = ForecastVolume.dailyMinimums(
            snapshots: snapshots,
            spot: spot,
            weightKg: profile.weightKg,
            skill: profile.skillLevel,
            age: profile.age
        )
        guard gemini.isConfigured else { return baseline }

        // Build one representative session per day (same grouping/peak-pick the rule path uses),
        // ordered by date, so Gemini's `dayIndex` lines up.
        let calendar = Calendar.current
        let groups = Dictionary(grouping: snapshots) { calendar.startOfDay(for: $0.timestamp) }
        let days = groups.keys.sorted().prefix(7)
        let representatives: [(date: Date, snapshot: ConditionsSnapshot)] = days.compactMap { day in
            guard let daySnaps = groups[day],
                  let peak = daySnaps.max(by: {
                      ForecastQuality.score($0, spot: spot) < ForecastQuality.score($1, spot: spot)
                  }) else { return nil }
            return (date: day, snapshot: peak)
        }
        guard !representatives.isEmpty else { return baseline }

        do {
            let result = try await gemini.forecast(
                profile: profile,
                spot: spot,
                dailyConditions: representatives,
                preferences: RecFeedback.preferenceSummary(from: feedback)
            )
            return result.isEmpty ? baseline : result
        } catch {
            return baseline
        }
    }
}
