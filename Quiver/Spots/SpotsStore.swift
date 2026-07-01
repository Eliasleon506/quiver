import Foundation

@MainActor
final class SpotsStore: ObservableObject {
    @Published private(set) var spots: [Spot] = []

    init() { load() }

    func load() {
        guard let url = Bundle.main.url(forResource: "spots", withExtension: "json") else {
            assertionFailure("spots.json missing from bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            spots = try JSONDecoder().decode([Spot].self, from: data)
        } catch {
            assertionFailure("Failed to load spots: \(error)")
        }
    }

    func spot(id: String) -> Spot? {
        spots.first(where: { $0.id == id })
    }

    func grouped() -> [(SpotRegion, [Spot])] {
        let groups = Dictionary(grouping: spots, by: { $0.region })
        return SpotRegion.allCases.compactMap { region in
            guard let s = groups[region], !s.isEmpty else { return nil }
            return (region, s)
        }
    }
}
