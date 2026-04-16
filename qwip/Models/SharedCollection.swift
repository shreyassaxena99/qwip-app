import Foundation

struct SharedCollection: Decodable {
    let id: String
    let name: String
    let description: String?
    let spotCount: Int
    let spots: [SpotPin]
}
