import Foundation

struct Collection: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let isShareable: Bool
    let spotCount: Int
    let createdAt: Date
    let updatedAt: Date
}
