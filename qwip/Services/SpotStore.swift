import Foundation
import Observation

@Observable
final class SpotStore {
    var spots: [SpotPin] = []
    var selectedCategory: SpotCategory? = nil
    var filterOpenNow: Bool = false
    var filterWifi: Bool = false
    var filterNoiseLevel: NoiseLevel? = nil
    var filterCollectionId: String? = nil
    var collectionSpotIds: Set<String>? = nil
    var isLoading = false
    var loadError: String? = nil

    var filteredSpots: [SpotPin] {
        spots.filter { spot in
            if let cat = selectedCategory, spot.category != cat { return false }
            if filterOpenNow, spot.isOpenNow != true { return false }
            if filterWifi, !spot.wifiAvailable { return false }
            if let noise = filterNoiseLevel, spot.noiseMatrix?.currentLevel() != noise { return false }
            if let ids = collectionSpotIds, !ids.contains(spot.id) { return false }
            return true
        }
    }

    var additionalFilterCount: Int {
        (filterOpenNow ? 1 : 0) + (filterWifi ? 1 : 0) + (filterNoiseLevel != nil ? 1 : 0) + (filterCollectionId != nil ? 1 : 0)
    }

    var hasAdditionalFilters: Bool { additionalFilterCount > 0 }

    func clearAdditionalFilters() {
        filterOpenNow = false
        filterWifi = false
        filterNoiseLevel = nil
        filterCollectionId = nil
        collectionSpotIds = nil
    }

    func setCollectionFilter(id: String, spotIds: Set<String>) {
        filterCollectionId = id
        collectionSpotIds = spotIds
    }

    func clearCollectionFilter() {
        filterCollectionId = nil
        collectionSpotIds = nil
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
