import Foundation
import Observation

@Observable
final class SpotStore {
    var spots: [SpotPin] = []
    var selectedCategory: SpotCategory? = nil
    var filterOpenNow: Bool = false
    var filterWifi: Bool = false
    var filterNoiseLevel: NoiseLevel? = nil
    var displayName: String = "Alex"
    var emailOptIn: Bool = false
    var isLoading = false
    var loadError: String? = nil

    var filteredSpots: [SpotPin] {
        spots.filter { spot in
            if let cat = selectedCategory, spot.category != cat { return false }
            if filterOpenNow, spot.isOpenNow != true { return false }
            if filterWifi, !spot.wifiAvailable { return false }
            if let noise = filterNoiseLevel, spot.noiseMatrix?.currentLevel() != noise { return false }
            return true
        }
    }

    var additionalFilterCount: Int {
        (filterOpenNow ? 1 : 0) + (filterWifi ? 1 : 0) + (filterNoiseLevel != nil ? 1 : 0)
    }

    var hasAdditionalFilters: Bool { additionalFilterCount > 0 }

    func clearAdditionalFilters() {
        filterOpenNow = false
        filterWifi = false
        filterNoiseLevel = nil
    }

    func loadSpots() async {
        isLoading = true
        loadError = nil
        do {
            spots = try await SpotAPIClient.shared.fetchSpots()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

}
