import Foundation

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

    var errorDescription: String? {
        switch self {
        case .saveFailed(let code): return "Profile save failed (server error \(code))."
        }
    }
}
