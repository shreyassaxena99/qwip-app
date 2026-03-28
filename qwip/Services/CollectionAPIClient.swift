import Foundation
import Supabase

// MARK: - Errors

enum CollectionAPIError: LocalizedError {
    case notAuthenticated
    case serverError(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to manage collections."
        case .serverError(let code): return "Server error (\(code))."
        case .decodingError: return "Couldn't parse the server response."
        }
    }
}

// MARK: - Request bodies

private struct CreateCollectionBody: Encodable {
    let name: String
    let description: String?
    let isShareable: Bool
}
private struct UpdateCollectionBody: Encodable {
    let name: String
    let description: String?
    let isShareable: Bool
}
private struct AddSpotToCollectionBody: Encodable { let spotId: String }

// MARK: - Response wrappers

private struct CollectionsResponse: Decodable { let collections: [Collection] }

// MARK: - Client

struct CollectionAPIClient {
    static let shared = CollectionAPIClient()

    private let baseURL = URL(string: "https://spotsvc.up.railway.app")!

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

    // MARK: - Auth helpers

    private func bearerToken() throws -> String {
        guard let token = supabase.auth.currentSession?.accessToken else {
            throw CollectionAPIError.notAuthenticated
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

    // MARK: - Collections

    /// GET /me/collections
    func fetchCollections() async throws -> [Collection] {
        let url = baseURL.appendingPathComponent("me/collections")
        let req = try authedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw CollectionAPIError.serverError(status) }
        do {
            return try decoder.decode(CollectionsResponse.self, from: data).collections
        } catch {
            throw CollectionAPIError.decodingError(error)
        }
    }

    /// POST /me/collections
    func createCollection(name: String, description: String?, isShareable: Bool) async throws -> Collection {
        let url = baseURL.appendingPathComponent("me/collections")
        var req = try authedRequest(url: url, method: "POST")
        req.httpBody = try encoder.encode(CreateCollectionBody(name: name, description: description, isShareable: isShareable))
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw CollectionAPIError.serverError(status) }
        do {
            return try decoder.decode(Collection.self, from: data)
        } catch {
            throw CollectionAPIError.decodingError(error)
        }
    }

    /// PATCH /me/collections/{id}
    func updateCollection(id: String, name: String, description: String?, isShareable: Bool) async throws -> Collection {
        let url = baseURL.appendingPathComponent("me/collections/\(id)")
        var req = try authedRequest(url: url, method: "PATCH")
        req.httpBody = try encoder.encode(UpdateCollectionBody(name: name, description: description, isShareable: isShareable))
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw CollectionAPIError.serverError(status) }
        do {
            return try decoder.decode(Collection.self, from: data)
        } catch {
            throw CollectionAPIError.decodingError(error)
        }
    }

    /// DELETE /me/collections/{id} — 204, spots remain saved
    func deleteCollection(id: String) async throws {
        let url = baseURL.appendingPathComponent("me/collections/\(id)")
        let req = try authedRequest(url: url, method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw CollectionAPIError.serverError(status) }
    }

    // MARK: - Collection spots

    /// POST /me/collections/{collectionId}/spots — also saves the spot if not already saved
    func addSpotToCollection(collectionId: String, spotId: String) async throws -> SavedSpotEntry {
        let url = baseURL.appendingPathComponent("me/collections/\(collectionId)/spots")
        var req = try authedRequest(url: url, method: "POST")
        req.httpBody = try encoder.encode(AddSpotToCollectionBody(spotId: spotId))
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw CollectionAPIError.serverError(status) }
        do {
            return try decoder.decode(SavedSpotEntry.self, from: data)
        } catch {
            throw CollectionAPIError.decodingError(error)
        }
    }

    /// DELETE /me/collections/{collectionId}/spots/{spotId} — spot stays saved
    func removeSpotFromCollection(collectionId: String, spotId: String) async throws {
        let url = baseURL.appendingPathComponent("me/collections/\(collectionId)/spots/\(spotId)")
        let req = try authedRequest(url: url, method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw CollectionAPIError.serverError(status) }
    }
}
