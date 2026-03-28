import Foundation

struct Collection: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let collectionDescription: String?
    let isShareable: Bool
    let spotCount: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, isShareable, spotCount, createdAt, updatedAt
        case collectionDescription = "description"
    }
}
