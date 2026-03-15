import Foundation
import Observation

@Observable
@MainActor
final class SavedSpotService {

    // MARK: - State

    private(set) var savedEntries: [SavedSpotEntry] = []
    private(set) var isLoading = false
    private(set) var loadError: String? = nil

    // MARK: - Read

    func isSaved(_ spotId: String) -> Bool {
        savedEntries.contains { $0.id == spotId }
    }

    // MARK: - Load

    /// Fetches all saved spots. Clears any previous error immediately so
    /// the error banner dismisses as soon as the user taps Retry.
    func load() async {
        isLoading = true
        loadError = nil
        do {
            savedEntries = try await SavedSpotAPIClient.shared.fetchSavedSpots()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Save (optimistic)

    /// Inserts a stub entry immediately, then replaces it with the real
    /// server response. Removes the stub and rethrows on failure.
    func save(spot: SpotPin) async throws {
        let stub = SavedSpotEntry(spot: spot, savedAt: .now, collectionIds: [])
        savedEntries.insert(stub, at: 0)
        do {
            let real = try await SavedSpotAPIClient.shared.saveSpot(spotId: spot.id)
            if let index = savedEntries.firstIndex(where: { $0.id == stub.id }) {
                savedEntries[index] = real
            }
        } catch {
            savedEntries.removeAll { $0.id == stub.id }
            throw error
        }
    }

    // MARK: - Unsave (optimistic)

    /// Removes the entry immediately, then re-inserts at the original
    /// position if the network call fails.
    func unsave(spotId: String) async throws {
        guard let index = savedEntries.firstIndex(where: { $0.id == spotId }) else { return }
        let captured = savedEntries[index]
        savedEntries.remove(at: index)
        do {
            try await SavedSpotAPIClient.shared.unsaveSpot(spotId: spotId)
        } catch {
            let safeIndex = min(index, savedEntries.count)
            savedEntries.insert(captured, at: safeIndex)
            throw error
        }
    }
}
