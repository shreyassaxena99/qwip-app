import Testing
@testable import qwip
import Foundation

struct qwipTests {

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

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        decoder.dateDecodingStrategy = .formatted(formatter)

        let collection = try decoder.decode(Collection.self, from: json)
        #expect(collection.id == "abc-123")
        #expect(collection.name == "Morning Cafes")
        #expect(collection.spotCount == 3)
        #expect(collection.isShareable == false)
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
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        decoder.dateDecodingStrategy = .formatted(formatter)

        let response = try decoder.decode(CollectionsResponse.self, from: json)
        #expect(response.collections.count == 1)
        #expect(response.collections[0].name == "Morning Cafes")
    }
}
