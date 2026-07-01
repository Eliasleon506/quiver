import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingFlow()
            } else {
                RootView()
            }
        }
    }
}
