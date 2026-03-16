import Foundation
import Supabase

// MARK: - Errors

enum SavedSpotAPIError: LocalizedError {
    case notAuthenticated
    case serverError(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to save spots."
        case .serverError(let code):
            return "Server error (\(code))."
        case .decodingError:
            return "Couldn't parse the server response."
        }
    }
}

// MARK: - Response wrappers

private struct SavedSpotsResponse: Decodable {
    let spots: [SavedSpotEntry]
}

// MARK: - Request body

private struct SaveSpotBody: Encodable {
    // Encoded to snake_case ("spot_id", "collection_ids") by the encoder's .convertToSnakeCase strategy
    let spotId: String
    let collectionIds: [String]
}

// MARK: - Client

struct SavedSpotAPIClient {
    static let shared = SavedSpotAPIClient()

    private let baseURL = URL(string: "https://spotsvc.up.railway.app")!

    /// Decodes Date fields using Supabase's fractional-second ISO 8601 format.
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        d.dateDecodingStrategy = .formatted(formatter)
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: - Auth

    private func bearerToken() throws -> String {
        // currentSession is the synchronous in-memory accessor on GoTrueClient
        guard let token = supabase.auth.currentSession?.accessToken else {
            throw SavedSpotAPIError.notAuthenticated
        }
        return token
    }

    private func authedRequest(url: URL, method: String = "GET") throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(try bearerToken())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    // MARK: - Endpoints

    /// GET /me/saved-spots — returns all saved spots for the current user, newest first.
    /// Pass `collectionId` to filter to a specific collection.
    func fetchSavedSpots(collectionId: String? = nil) async throws -> [SavedSpotEntry] {
        var url = baseURL.appendingPathComponent("me/saved-spots")
        if let collectionId {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "collection_id", value: collectionId)]
            url = components.url ?? url
        }
        let req = try authedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw SavedSpotAPIError.serverError(status) }
        do {
            return try decoder.decode(SavedSpotsResponse.self, from: data).spots
        } catch {
            print("🔴 [SavedSpotAPIClient] Raw response:\n\(String(data: data, encoding: .utf8) ?? "<non-utf8>")")
            print("🔴 [SavedSpotAPIClient] Decode error: \(error)")
            throw SavedSpotAPIError.decodingError(error)
        }
    }

    /// POST /me/saved-spots — saves a spot and returns the created entry.
    func saveSpot(spotId: String, collectionIds: [String] = []) async throws -> SavedSpotEntry {
        let url = baseURL.appendingPathComponent("me/saved-spots")
        var req = try authedRequest(url: url, method: "POST")
        req.httpBody = try encoder.encode(SaveSpotBody(spotId: spotId, collectionIds: collectionIds))
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw SavedSpotAPIError.serverError(status) }
        do {
            return try decoder.decode(SavedSpotEntry.self, from: data)
        } catch {
            throw SavedSpotAPIError.decodingError(error)
        }
    }

    /// DELETE /me/saved-spots/{spotId} — unsaves a spot.
    /// A 404 is treated as success (spot was already not saved).
    func unsaveSpot(spotId: String) async throws {
        let url = baseURL.appendingPathComponent("me/saved-spots/\(spotId)")
        let req = try authedRequest(url: url, method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return }
        guard (200...299).contains(status) else { throw SavedSpotAPIError.serverError(status) }
    }
}
