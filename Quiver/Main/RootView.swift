import SwiftUI
import SwiftData

struct RootView: View {
    @StateObject private var spotsStore = SpotsStore()
    @Query private var profiles: [UserProfile]
    @State private var selectedSpot: Spot?
    @State private var selectedTab: Tab = .spots
    @State private var showingProfileEditor = false
    @State private var showingAccuracy = false

    enum Tab: Hashable {
        case spots, quiver
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                SpotPickerView { spot in
                    selectedSpot = spot
                }
                .navigationDestination(item: $selectedSpot) { spot in
                    RecommendationView(spot: spot)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingAccuracy = true
                        } label: {
                            Label("Forecast accuracy", systemImage: "chart.xyaxis.line")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingProfileEditor = true
                        } label: {
                            Label("Profile", systemImage: "gearshape")
                        }
                    }
                }
            }
            .tabItem { Label("Spots", systemImage: "mappin.and.ellipse") }
            .tag(Tab.spots)

            NavigationStack {
                QuiverView()
            }
            .tabItem { Label("Quiver", systemImage: "tray.full") }
            .tag(Tab.quiver)
        }
        .environmentObject(spotsStore)
        .sheet(isPresented: $showingProfileEditor) {
            if let profile = profiles.first {
                NavigationStack { ProfileEditorView(profile: profile) }
            }
        }
        .sheet(isPresented: $showingAccuracy) {
            ForecastAccuracyView(spotsStore: spotsStore)
        }
    }
}
