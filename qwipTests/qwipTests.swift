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

    @Test func collectionDecodesFromJSON() throws {
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
        #expect(collection.id == "abc-123")
        #expect(collection.name == "Morning Cafes")
        #expect(collection.spotCount == 3)
        #expect(collection.isShareable == false)
        // Verify the date format is correct
        let expected = makeFormatter().date(from: "2026-03-16T09:00:00.000+0000")!
        #expect(collection.createdAt == expected)
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
            id: "abc", name: "Test", isShareable: false, spotCount: 1,
            createdAt: Date(), updatedAt: Date()
        )
        let b = Collection(
            id: "abc", name: "Test", isShareable: false, spotCount: 1,
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
