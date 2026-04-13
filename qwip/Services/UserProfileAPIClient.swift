import Foundation

struct UserProfile {
    var workingStyle: String?
    var homeArea: String?
    var workArea: String?
}

struct UserProfileAPIClient {

    private static let baseURL = "https://spotsvc.up.railway.app"

    /// Returns true if a profile exists, false if `{"exists": false}` is returned.
    /// Returns true on any network/decode error — safe default is to skip onboarding.
    static func fetchExists(userId: String, token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/users/profile/\(userId)") else { return true }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return true }
        struct NoProfileBody: Decodable { let exists: Bool }
        if let body = try? JSONDecoder().decode(NoProfileBody.self, from: data), !body.exists {
            return false
        }
        return true
    }

    /// Fetches the full onboarding profile. Returns a UserProfile with nil fields if `exists == false`.
    /// Throws ProfileError.fetchFailed on network or server errors.
    static func fetchProfile(userId: String, token: String) async throws -> UserProfile {
        guard let url = URL(string: "\(baseURL)/users/profile/\(userId)") else {
            throw ProfileError.fetchFailed(0)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw ProfileError.fetchFailed(status) }
        struct ProfileResponse: Decodable {
            let exists: Bool
            let workingStyle: String?
            let homeArea: String?
            let workArea: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let body = try decoder.decode(ProfileResponse.self, from: data)
        return UserProfile(
            workingStyle: body.workingStyle,
            homeArea: body.homeArea,
            workArea: body.workArea
        )
    }

    /// Posts the user's profile. Throws on server errors; callers should fail silently.
    static func saveProfile(
        userId: String,
        token: String,
        workingStyle: String?,
        homeArea: String?,
        workArea: String?
    ) async throws {
        guard let url = URL(string: "\(baseURL)/users/profile") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = ["user_id": userId]
        if let v = workingStyle { body["working_style"] = v }
        if let v = homeArea    { body["home_area"] = v }
        if let v = workArea    { body["work_area"] = v }
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw ProfileError.saveFailed(status) }
    }
}

// MARK: - Errors

enum ProfileError: LocalizedError {
    case saveFailed(Int)
    case fetchFailed(Int)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let code):  return "Profile save failed (server error \(code))."
        case .fetchFailed(let code): return "Couldn't load profile (server error \(code))."
        }
    }
}
