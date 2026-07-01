import SwiftUI
import SwiftData

struct RecommendationView: View {
    let spot: Spot
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(sort: \Board.addedAt, order: .reverse) private var boards: [Board]
    @Query(sort: \RecFeedback.createdAt, order: .reverse) private var feedback: [RecFeedback]

    @State private var conditions: ConditionsSnapshot?
    @State private var recommendation: Recommendation?
    @State private var error: String?
    @State private var loading: Bool = true
    @State private var showingSizingSheet: Bool = false

    // Feedback (per loaded recommendation).
    @State private var feedbackGiven: Bool = false
    @State private var showCommentField: Bool = false
    @State private var commentText: String = ""

    // True while the AI rec is being fetched in the background (baseline already shown).
    @State private var refiningWithAI: Bool = false

    // Advisory banner: collapsed (icon + title) until tapped.
    @State private var advisoryExpanded: Bool = false

    private let provider: ConditionsProvider = CompositeConditionsProvider.shared
    private let recommender = Recommender()
    private let gemini = GeminiRecommender()
    private let wetsuitSelector = WetsuitSelector()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if loading {
                    ProgressView("Fetching conditions…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else if let error {
                    errorCard(error)
                } else if let rec = recommendation, let snap = conditions {
                    if let advisory = rec.advisory {
                        advisoryBanner(advisory)
                    }
                    conditionsCard(snap)
                    forecastLink
                    recommendationCard(rec)
                    if !rec.quiverMatches.isEmpty {
                        quiverCard(rec.quiverMatches)
                    } else {
                        emptyQuiverHint
                    }
                    dimensionCard(rec.dimensionSuggestion)
                }
            }
            .padding()
        }
        .navigationTitle(spot.name)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showingSizingSheet) {
            NavigationStack {
                DimensionRecommenderView()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(spot.region.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let notes = spot.notes {
                Text(notes).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var forecastLink: some View {
        NavigationLink {
            ForecastView(spot: spot)
        } label: {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                Text("7-day forecast & best window")
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .font(.callout.weight(.medium))
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func advisoryBanner(_ a: Advisory) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { advisoryExpanded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(a.title).font(.headline)
                        Spacer()
                        Image(systemName: advisoryExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if advisoryExpanded {
                        Text(a.detail).font(.callout).foregroundStyle(.secondary)
                        Text("Recommendation still shown below — biased toward forgiving boards.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func conditionsCard(_ snap: ConditionsSnapshot) -> some View {
        let heightFt = snap.primarySwellHeightFt.map { String(format: "%.1f ft", $0) } ?? "—"
        let period = snap.primarySwellPeriodS.map { String(format: "%.0fs", $0) } ?? "—"
        let wind = snap.windSpeedKt.map { String(format: "%.0f kt", $0) } ?? "—"
        let windDir = snap.windDirDeg.map { Units.compassPoint(degrees: $0) } ?? "—"
        let tide: String = {
            guard let h = snap.tideHeightM else { return "—" }
            let ft = h * 3.28084
            let trend = snap.tideTrend.map { "  (\($0.rawValue))" } ?? ""
            return String(format: "%.1f ft%@", ft, trend)
        }()

        return VStack(alignment: .leading, spacing: 10) {
            Text("Conditions").font(.headline)
            // Swell: one compact compass (arrow vs. the spot's optimal window) replaces "SW (270°)".
            HStack {
                Text("Swell").foregroundStyle(.secondary)
                Spacer()
                Text("\(heightFt) @ \(period)").font(.body.monospacedDigit())
                if let dir = snap.primarySwellDirDeg {
                    SwellCompassView(swellDirDeg: dir, spot: spot).frame(width: 26, height: 26)
                }
            }
            statRow("Wind", "\(windDir) \(wind)")
            statRow("Tide", tide)
            if let tempF = snap.waterTempF {
                statRow("Water", waterRow(tempF: tempF, snap: snap))
            }
            BuoyComparisonBadge(snapshot: snap, buoyId: spot.ndbcBuoyId)
                .padding(.top, 2)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    /// "58°F · 4/3 full" — water temp plus the suit the surfer will wear (or the ideal if they own none).
    private func waterRow(tempF: Double, snap: ConditionsSnapshot) -> String {
        guard let profile = profiles.first else { return String(format: "%.0f°F", tempF) }
        let w = wetsuitSelector.resolve(waterTempF: snap.waterTempF, profile: profile)
        let suit = w.selected?.displayName ?? w.ideal?.displayName ?? "trunks"
        return String(format: "%.0f°F · %@", tempF, suit)
    }

    private func recommendationCard(_ rec: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ride").font(.headline)
                Spacer()
                if refiningWithAI {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Refining with AI…")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    Label(rec.isAIGenerated ? "AI" : "Rules",
                          systemImage: rec.isAIGenerated ? "sparkles" : "slider.horizontal.3")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(rec.primaryType.displayName)
                .font(.title2.bold())
            Text("Target volume: \(rec.targetVolume.formatted())")
                .font(.title3)
                .foregroundStyle(.secondary)
            // One concise "Why" up top; any remaining rationale tucked behind a disclosure.
            if let why = rec.rationale.first {
                Text(why).font(.callout)
                let rest = Array(rec.rationale.dropFirst())
                if !rest.isEmpty {
                    DisclosureGroup("More detail") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(rest.enumerated()), id: \.offset) { _, line in
                                Text("• \(line)").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                    }
                    .font(.callout)
                }
            }
            if !rec.alternateTypes.isEmpty {
                Text("Alternatives: " + rec.alternateTypes.map(\.displayName).joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 4)
            feedbackRow(rec)
        }
        .padding()
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func feedbackRow(_ rec: Recommendation) -> some View {
        if feedbackGiven {
            Label("Thanks for the feedback", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        } else {
            HStack(spacing: 16) {
                Text("Good call?").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { saveFeedback(rec, up: true) } label: {
                    Image(systemName: "hand.thumbsup")
                }
                Button { showCommentField.toggle() } label: {
                    Image(systemName: "hand.thumbsdown")
                }
            }
            .buttonStyle(.bordered)
            if showCommentField {
                TextField("What was off? (optional)", text: $commentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                HStack {
                    Spacer()
                    Button("Submit") { saveFeedback(rec, up: false) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func quiverCard(_ matches: [QuiverMatch]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("From your quiver").font(.headline)
            ForEach(Array(matches.enumerated()), id: \.offset) { _, m in
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.board.nickname ?? m.board.type.displayName).font(.body.weight(.semibold))
                    Text(m.rationale).font(.callout).foregroundStyle(.secondary)
                    DimensionLabel(lengthIn: m.board.lengthIn, widthIn: m.board.widthIn,
                                   thicknessIn: m.board.thicknessIn, volumeL: m.board.effectiveVolumeL)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyQuiverHint: some View {
        Text("Add boards to your quiver to get specific board picks.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func dimensionCard(_ d: DimensionSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("If you bought one for today").font(.headline)
            DimensionLabel(lengthIn: d.lengthIn, widthIn: d.widthIn,
                           thicknessIn: d.thicknessIn, volumeL: d.volumeL, typeName: d.type.displayName)
                .font(.callout.monospacedDigit())
            Button {
                showingSizingSheet = true
            } label: {
                Label("Dial it in", systemImage: "ruler")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Couldn't load conditions").font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary)
            Button("Retry") { Task { await reload() } }
                .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }

    /// Progressive load: show the instant rule baseline as soon as conditions land, then quietly
    /// swap in Gemini's recommendation when it returns. This removes the multi-second blank wait —
    /// the screen populates immediately and only the "Ride" card refines in place.
    @MainActor
    private func reload() async {
        loading = true
        error = nil
        // Reset per-rec feedback UI.
        feedbackGiven = false
        showCommentField = false
        commentText = ""
        refiningWithAI = false

        do {
            let snap = try await provider.currentConditions(spot: spot)
            self.conditions = snap
            guard let profile = profiles.first else { loading = false; return }

            // Resolve today's wetsuit once (water temp + owned rubber) — feeds both engines.
            let wetsuit = wetsuitSelector.resolve(waterTempF: snap.waterTempF, profile: profile)

            // 1. Instant: the rule baseline (also the offline/safety fallback).
            let baseline = recommender.recommend(
                profile: profile, spot: spot, conditions: snap, quiver: Array(boards)
            )
            self.recommendation = baseline
            self.loading = false

            // Forecast-accuracy backtest: grade any now-due prediction against the live buoy
            // reading, then log this fetch's future predictions. The 48-h forecast is already
            // cached by the currentConditions call above, so this adds no extra network round-trip.
            let recorder = BacktestRecorder(context: modelContext)
            recorder.reconcile(current: snap)
            if let forecast = try? await provider.forecast(spot: spot, hours: 48) {
                recorder.capture(forecast: forecast)
            }

            // 2. Upgrade: Gemini in the background; swap in when ready, keep baseline on any error.
            guard gemini.isConfigured else { return }
            refiningWithAI = true
            defer { refiningWithAI = false }
            do {
                let ai = try await gemini.recommend(
                    profile: profile,
                    spot: spot,
                    conditions: snap,
                    quiver: Array(boards),
                    preferences: RecFeedback.preferenceSummary(from: feedback),
                    wetsuit: wetsuit
                )
                self.recommendation = ai
                self.feedbackGiven = false   // rate the rec actually shown
            } catch {
                // Intentional silent fallback to the rule baseline (offline resilience).
                // Logged so dev builds can see *why* the AI path didn't take.
                #if DEBUG
                print("[Gemini] fell back to rule engine: \(error)")
                #endif
            }
        } catch {
            self.error = error.localizedDescription
            self.loading = false
        }
    }

    @MainActor
    private func saveFeedback(_ rec: Recommendation, up: Bool) {
        let d = rec.dimensionSuggestion
        let snapshot = RecSnapshot(
            boardType: rec.primaryType.rawValue,
            lengthIn: d.lengthIn,
            widthIn: d.widthIn,
            thicknessIn: d.thicknessIn,
            volumeL: rec.targetVolume.midpointL,
            conditionsSummary: conditionsSummary(),
            wasAIGenerated: rec.isAIGenerated
        )
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = RecFeedback(
            spotId: spot.id,
            ratingUp: up,
            comment: trimmed.isEmpty ? nil : trimmed,
            snapshot: snapshot
        )
        modelContext.insert(entry)
        try? modelContext.save()
        feedbackGiven = true
        showCommentField = false
    }

    private func conditionsSummary() -> String {
        guard let c = conditions else { return "—" }
        let h = c.primarySwellHeightFt.map { String(format: "%.1f ft", $0) } ?? "—"
        let p = c.primarySwellPeriodS.map { String(format: "%.0fs", $0) } ?? "—"
        let wind = c.windSpeedKt.map { String(format: "%.0f kt", $0) } ?? "—"
        return "\(h) @ \(p), wind \(wind)"
    }
}

// MARK: - Shared small views (Phase 3 declutter)

/// One compact compass glyph: an arrow for the incoming swell, tinted by how well it lines up with
/// the spot's optimal window (accent = in window, orange = marginal, red = shadowed). Replaces the
/// duplicated "SW (270°)" text. `swellDirDeg` is the direction the swell comes *from* (compass deg).
struct SwellCompassView: View {
    let swellDirDeg: Double
    let spot: Spot

    private var tint: Color {
        let outside = spot.degreesOutsideWindow(swellDirDeg)
        if outside == 0 { return .accentColor }
        if outside <= 20 { return .orange }
        return .red
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            Circle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 2, height: 2)
                .offset(y: -11)   // tiny "N" reference dot at the top
            // arrow.down points south at 0°; rotating by the from-bearing makes it read as the
            // swell arriving from `swellDirDeg` toward the center.
            Image(systemName: "arrow.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .rotationEffect(.degrees(swellDirDeg))
        }
        .accessibilityLabel("Swell from \(Units.compassPoint(degrees: swellDirDeg))")
    }
}

/// Single source of truth for the "L × W × T ≈ V" board-dimension string. Apply `.font`/
/// `.foregroundStyle` at the call site. `typeName` prefixes the board type when shown standalone.
struct DimensionLabel: View {
    let lengthIn: Double
    let widthIn: Double
    let thicknessIn: Double
    let volumeL: Double
    var typeName: String? = nil

    var body: some View { Text(Self.string(lengthIn: lengthIn, widthIn: widthIn,
                                            thicknessIn: thicknessIn, volumeL: volumeL, typeName: typeName)) }

    static func lengthDisplay(_ lengthIn: Double) -> String {
        let feet = Int(lengthIn) / 12
        let inches = lengthIn.truncatingRemainder(dividingBy: 12)
        if inches < 0.05 { return "\(feet)'" }
        let inchStr = inches == floor(inches) ? "\(Int(inches))" : String(format: "%.1f", inches)
        return "\(feet)'\(inchStr)\""
    }

    static func string(lengthIn: Double, widthIn: Double, thicknessIn: Double,
                       volumeL: Double, typeName: String?) -> String {
        let dims = String(format: "%@  %.2f × %.2f  ≈ %.1f L",
                          lengthDisplay(lengthIn), widthIn, thicknessIn, volumeL)
        return typeName.map { "\($0)  \(dims)" } ?? dims
    }
}
