import Foundation
import Observation

@Observable
@MainActor
final class CollectionService {

    // MARK: - State

    private(set) var collections: [Collection] = []
    private(set) var isLoading = false
    private(set) var loadError: String? = nil

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        do {
            collections = try await CollectionAPIClient.shared.fetchCollections()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Create (optimistic)

    /// Returns the real (server-confirmed) Collection so callers can auto-tick it.
    /// The UUID stub id is guaranteed not to collide with server-generated UUIDs.
    @discardableResult
    func create(name: String, collectionDescription: String? = nil, isShareable: Bool = false) async throws -> Collection {
        let stubId = UUID().uuidString
        let stub = Collection(id: stubId, name: name, collectionDescription: collectionDescription,
                              isShareable: isShareable, spotCount: 0,
                              createdAt: .now, updatedAt: .now)
        collections.append(stub)
        do {
            let real = try await CollectionAPIClient.shared.createCollection(
                name: name, description: collectionDescription, isShareable: isShareable)
            if let index = collections.firstIndex(where: { $0.id == stubId }) {
                collections[index] = real
            }
            return real
        } catch {
            collections.removeAll { $0.id == stubId }
            throw error
        }
    }

    // MARK: - Rename (optimistic)

    func update(id: String, name: String, collectionDescription: String?, isShareable: Bool) async throws {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        let old = collections[index]
        collections[index] = Collection(id: old.id, name: name,
                                        collectionDescription: collectionDescription,
                                        isShareable: isShareable,
                                        spotCount: old.spotCount, createdAt: old.createdAt,
                                        updatedAt: .now)
        do {
            let updated = try await CollectionAPIClient.shared.updateCollection(
                id: id, name: name, description: collectionDescription, isShareable: isShareable)
            if let newIndex = collections.firstIndex(where: { $0.id == id }) {
                collections[newIndex] = updated
            }
        } catch {
            if let newIndex = collections.firstIndex(where: { $0.id == id }) {
                collections[newIndex] = old
            }
            throw error
        }
    }

    // MARK: - Delete (optimistic)

    func delete(id: String) async throws {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        let captured = collections[index]
        collections.remove(at: index)
        do {
            try await CollectionAPIClient.shared.deleteCollection(id: id)
        } catch {
            let safeIndex = min(index, collections.count)
            collections.insert(captured, at: safeIndex)
            throw error
        }
    }

    // MARK: - Spot membership

    /// Optimistically increments spotCount; reverts on failure.
    /// Returns the SavedSpotEntry from the server (contains updated collectionIds).
    @discardableResult
    func addSpot(spotId: String, toCollection collectionId: String) async throws -> SavedSpotEntry {
        incrementSpotCount(for: collectionId, by: 1)
        do {
            return try await CollectionAPIClient.shared.addSpotToCollection(
                collectionId: collectionId, spotId: spotId)
        } catch {
            incrementSpotCount(for: collectionId, by: -1)
            throw error
        }
    }

    /// Optimistically decrements spotCount; reverts on failure.
    func removeSpot(spotId: String, fromCollection collectionId: String) async throws {
        incrementSpotCount(for: collectionId, by: -1)
        do {
            try await CollectionAPIClient.shared.removeSpotFromCollection(
                collectionId: collectionId, spotId: spotId)
        } catch {
            incrementSpotCount(for: collectionId, by: 1)
            throw error
        }
    }

    // MARK: - Private helpers

    private func incrementSpotCount(for collectionId: String, by delta: Int) {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        let old = collections[index]
        collections[index] = Collection(id: old.id, name: old.name,
                                        collectionDescription: old.collectionDescription,
                                        isShareable: old.isShareable,
                                        spotCount: max(0, old.spotCount + delta),
                                        createdAt: old.createdAt, updatedAt: old.updatedAt)
    }
}
