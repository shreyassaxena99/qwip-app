import Foundation

// MARK: - API Error

enum SpotAPIError: LocalizedError {
    case notFound
    case serverError(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notFound: return "Spot not found."
        case .serverError(let code): return "Server error (\(code))."
        case .decodingError: return "Couldn't parse server response."
        }
    }
}

// MARK: - Response Wrapper

struct SpotsListResponse: Decodable {
    let spots: [SpotPin]
    let total: Int
}

// MARK: - Client

struct SpotAPIClient {
    static let shared = SpotAPIClient()

    private let baseURL = URL(string: "https://spotsvc.up.railway.app")!
    private let detailCache = NSCache<NSString, SpotDetailBox>()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func fetchSpots(category: SpotCategory? = nil, isOpenNow: Bool? = nil) async throws -> [SpotPin] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("spots"),
            resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = []
        if let category { items.append(URLQueryItem(name: "category", value: category.rawValue)) }
        if let isOpenNow { items.append(URLQueryItem(name: "is_open_now", value: isOpenNow ? "true" : "false")) }
        if !items.isEmpty { components.queryItems = items }

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SpotAPIError.serverError(status) }

        do {
            return try decoder.decode(SpotsListResponse.self, from: data).spots
        } catch {
            throw SpotAPIError.decodingError(error)
        }
    }

    func fetchSpotDetail(id: String) async throws -> SpotDetail {
        let key = id as NSString
        if let cached = detailCache.object(forKey: key) {
            return cached.detail
        }

        let url = baseURL.appendingPathComponent("spots/\(id)")
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw SpotAPIError.notFound }
        guard status == 200 else { throw SpotAPIError.serverError(status) }

        do {
            let detail = try decoder.decode(SpotDetail.self, from: data)
            print("[SpotAPIClient] fetchSpotDetail(\(id)) photos[\(detail.photos.count)]: \(detail.photos)")
            detailCache.setObject(SpotDetailBox(detail), forKey: key)
            return detail
        } catch {
            throw SpotAPIError.decodingError(error)
        }
    }
}

// NSCache requires AnyObject values, so we box SpotDetail (a struct) in a class.
private final class SpotDetailBox: NSObject {
    let detail: SpotDetail
    init(_ detail: SpotDetail) { self.detail = detail }
}
