import SwiftUI
import SwiftData
import MapKit

struct SpotPickerView: View {
    @EnvironmentObject private var spotsStore: SpotsStore
    @Environment(\.modelContext) private var modelContext
    @Query private var favorites: [FavoriteSpot]
    @State private var selectedTab: Tab = .list
    var onPick: (Spot) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case list, map
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    private var favoriteIds: Set<String> { Set(favorites.map(\.spotId)) }

    private var favoriteSpots: [Spot] {
        spotsStore.spots
            .filter { favoriteIds.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                ForEach(Tab.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .list:
                listView
            case .map:
                MapPickerView(spots: spotsStore.spots, onPick: onPick)
            }
        }
        .navigationTitle("Pick a spot")
    }

    private var listView: some View {
        List {
            if !favoriteSpots.isEmpty {
                Section("Favorites") {
                    ForEach(favoriteSpots) { spot in
                        spotRow(spot)
                    }
                }
            }
            ForEach(spotsStore.grouped(), id: \.0) { region, spots in
                Section(region.displayName) {
                    ForEach(spots) { spot in
                        spotRow(spot)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func spotRow(_ spot: Spot) -> some View {
        let isFav = favoriteIds.contains(spot.id)
        return Button {
            onPick(spot)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        if isFav {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                        Text(spot.name).font(.body)
                    }
                    if let notes = spot.notes {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                toggleFavorite(spot)
            } label: {
                Label(isFav ? "Unfavorite" : "Favorite",
                      systemImage: isFav ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
    }

    private func toggleFavorite(_ spot: Spot) {
        if let existing = favorites.first(where: { $0.spotId == spot.id }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteSpot(spotId: spot.id))
        }
        try? modelContext.save()
    }
}

private struct MapPickerView: View {
    let spots: [Spot]
    let onPick: (Spot) -> Void

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.35, longitude: -119.55),
            span: MKCoordinateSpan(latitudeDelta: 0.65, longitudeDelta: 0.9)
        )
    )

    var body: some View {
        Map(position: $position) {
            ForEach(spots) { spot in
                Annotation(spot.name, coordinate: spot.coordinate) {
                    Button {
                        onPick(spot)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.tint)
                            Text(spot.name)
                                .font(.caption2)
                                .padding(2)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
