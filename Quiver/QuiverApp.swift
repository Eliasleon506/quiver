import SwiftUI
import SwiftData

@main
struct QuiverApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: UserProfile.self, Board.self, FavoriteSpot.self, RecFeedback.self, ForecastRecord.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
