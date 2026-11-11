import Testing
@testable import qwip
import Foundation

struct qwipTests {

    // MARK: - Shared helpers

    private func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        return formatter
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .formatted(makeFormatter())
        return decoder
    }

    // MARK: - Collection decoding

    @Test func savedPodSpotDecodesFromJSON() throws {
        let json = """
        {
            "spot": {
                "id": "pod-1", "name": "Qwip Pod", "short_address": "London",
                "latitude": 51.5, "longitude": -0.1, "category": "pod",
                "access_type": "purchase_required", "wifi_available": true,
                "power_outlets": true, "noise_matrix": null, "rating": null,
                "is_open_now": true, "is_in_use": false,
                "pod_id": "25993183-3c63-420b-a8cd-be3ce1283226", "cover_photo": null
            },
            "saved_at": "2026-11-11T09:00:00.000+0000",
            "collection_ids": []
        }
        """.data(using: .utf8)!

        let entry = try makeDecoder().decode(SavedSpotEntry.self, from: json)
        #expect(entry.spot.category.rawValue == "pod")
        #expect(entry.spot.category.displayName == "Pod")
        #expect(entry.spot.isInUse == false)
        #expect(entry.spot.podId == "25993183-3c63-420b-a8cd-be3ce1283226")
    }

    @Test func collectionDecodesFromJSON() throws {
        let json = """
        {
            "id": "abc-123",
            "name": "Morning Cafes",
            "description": null,
            "is_shareable": false,
            "spot_count": 3,
            "created_at": "2026-03-16T09:00:00.000+0000",
            "updated_at": "2026-03-16T09:00:00.000+0000"
        }
        """.data(using: .utf8)!

        let collection = try makeDecoder().decode(Collection.self, from: json)
        #expect(collection.id == "abc-123")
        #expect(collection.name == "Morning Cafes")
        #expect(collection.spotCount == 3)
        #expect(collection.isShareable == false)
        #expect(collection.collectionDescription == nil)
        // Verify the date format is correct
        let expected = makeFormatter().date(from: "2026-03-16T09:00:00.000+0000")!
        #expect(collection.createdAt == expected)
    }

    @Test func collectionDecodesNullDescription() throws {
        let json = """
        {
            "id": "abc-123",
            "name": "Morning Cafes",
            "description": null,
            "is_shareable": false,
            "spot_count": 3,
            "created_at": "2026-03-16T09:00:00.000+0000",
            "updated_at": "2026-03-16T09:00:00.000+0000"
        }
        """.data(using: .utf8)!
        let collection = try makeDecoder().decode(Collection.self, from: json)
        #expect(collection.collectionDescription == nil)
    }

    @Test func collectionDecodesDescription() throws {
        let json = """
        {
            "id": "abc-123",
            "name": "Morning Cafes",
            "description": "Great spots for early birds",
            "is_shareable": false,
            "spot_count": 3,
            "created_at": "2026-03-16T09:00:00.000+0000",
            "updated_at": "2026-03-16T09:00:00.000+0000"
        }
        """.data(using: .utf8)!
        let collection = try makeDecoder().decode(Collection.self, from: json)
        #expect(collection.collectionDescription == "Great spots for early birds")
    }

    @Test func collectionMissingDescriptionDecodesNil() throws {
        let json = """
        {
            "id": "abc-123",
            "name": "Morning Cafes",
            "is_shareable": false,
            "spot_count": 3,
            "created_at": "2026-03-16T09:00:00.000+0000",
            "updated_at": "2026-03-16T09:00:00.000+0000"
        }
        """.data(using: .utf8)!
        let collection = try makeDecoder().decode(Collection.self, from: json)
        #expect(collection.collectionDescription == nil)
    }

    @Test func collectionsResponseDecodesFromJSON() throws {
        let json = """
        {
            "collections": [
                {
                    "id": "abc-123",
                    "name": "Morning Cafes",
                    "is_shareable": false,
                    "spot_count": 3,
                    "created_at": "2026-03-16T09:00:00.000+0000",
                    "updated_at": "2026-03-16T09:00:00.000+0000"
                }
            ]
        }
        """.data(using: .utf8)!

        struct CollectionsResponse: Decodable { let collections: [Collection] }
        let response = try makeDecoder().decode(CollectionsResponse.self, from: json)
        #expect(response.collections.count == 1)
        #expect(response.collections[0].name == "Morning Cafes")
    }

    @Test func collectionIsHashable() {
        let a = Collection(
            id: "abc", name: "Test", collectionDescription: nil, isShareable: false, spotCount: 1,
            createdAt: Date(), updatedAt: Date()
        )
        let b = Collection(
            id: "abc", name: "Test", collectionDescription: nil, isShareable: false, spotCount: 1,
            createdAt: a.createdAt, updatedAt: a.updatedAt
        )
        var set = Set<Collection>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }
}

@MainActor
struct SavedSpotServiceTests {

    @Test func updateCollectionIdsNoopsOnMissingEntry() {
        let service = SavedSpotService()
        // Guard path: calling on empty service should not crash and leave entries empty
        service.updateCollectionIds(spotId: "spot-1", collectionIds: ["col-1"])
        #expect(service.savedEntries.isEmpty)
    }
}

struct AppRouterTests {

    @Test func parsesValidCollectionURL() {
        let url = URL(string: "https://qwip.co.uk/collections/abc-123")!
        #expect(AppRouter.collectionId(from: url) == "abc-123")
    }

    @Test func ignoresNonCollectionURL() {
        let url = URL(string: "https://qwip.co.uk/spots/xyz")!
        #expect(AppRouter.collectionId(from: url) == nil)
    }

    @Test func ignoresGoogleOAuthURL() {
        let url = URL(string: "com.googleusercontent.apps.12345:/oauth2callback")!
        #expect(AppRouter.collectionId(from: url) == nil)
    }

    @Test func parsesCollectionIdWithTrailingPath() {
        // Defensive: only the first path component after /collections/ is the ID
        let url = URL(string: "https://qwip.co.uk/collections/abc-123/extra")!
        #expect(AppRouter.collectionId(from: url) == "abc-123")
    }
}
