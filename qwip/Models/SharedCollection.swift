import Foundation

struct SharedCollection: Decodable {
    let id: String
    let name: String
    let collectionDescription: String?
    let spotCount: Int
    let spots: [SpotPin]

    enum CodingKeys: String, CodingKey {
        case id, name, spotCount, spots
        case collectionDescription = "description"
    }
}
