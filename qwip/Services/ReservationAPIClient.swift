import Foundation
import OSLog

private let reservationAPILog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "qwip",
                                       category: "ReservationAPI")

enum ReservationAPIError: LocalizedError {
    case slotTaken
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .slotTaken: "That time has just been taken. Please choose another."
        case .server(let message): message
        case .invalidResponse: "We couldn't read the booking response. Please try again."
        }
    }
}

struct ReservationAPIClient {
    static let shared = ReservationAPIClient()
    private let baseURL = URL(string: "https://qwipsvc.up.railway.app")!

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw ReservationAPIError.invalidResponse
        }
        return decoder
    }()

    func pods(accessToken: String? = nil) async throws -> [ReservablePod] {
        guard let accessToken else {
            return try await get("api/reservations/pods", as: PodListResponse.self).pods
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/app-reservations/pods"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await self.request(request, as: PodListResponse.self).pods
    }

    func availability(podId: String, day: Date, accessToken: String) async throws -> ReservationAvailability {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/app-reservations/availability"), resolvingAgainstBaseURL: false)!
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = TimeZone(identifier: "Europe/London")!
        dateFormatter.dateFormat = "yyyy-MM-dd"
        components.queryItems = [
            URLQueryItem(name: "pod_id", value: podId),
            URLQueryItem(name: "day", value: dateFormatter.string(from: day))
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await self.request(request, as: ReservationAvailability.self)
    }

    func create(podId: String, startAt: Date, durationMinutes: Int,
                name: String, email: String, phone: String?, accessToken: String) async throws -> ReservationHold {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/app-reservations"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "pod_id": podId,
            "start_at": ISO8601DateFormatter().string(from: startAt),
            "duration_minutes": durationMinutes,
            "customer_name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "customer_email": email.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        if let phone, !phone.isEmpty { body["customer_phone"] = phone }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await self.request(request, as: ReservationHold.self)
    }

    func status(id: String) async throws -> ReservationStatus {
        try await get("api/reservations/\(id)/status", as: ReservationStatus.self)
    }

    func myBookings(accessToken: String) async throws -> [MyPodReservation] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/reservations/me"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await self.request(request, as: MyReservationsResponse.self).bookings
    }

    func accessCode(id: String, accessToken: String) async throws -> ReservationAccessCode {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/reservations/\(id)/access-code"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await self.request(request, as: ReservationAccessCode.self)
    }

    func uploadCheckInPhoto(id: String, jpegData: Data,
                            accessToken: String) async throws -> ReservationCheckInPhoto {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/reservations/\(id)/check-in-photo"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"check-in.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpegData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return try await self.request(request, as: ReservationCheckInPhoto.self)
    }

    func resumePayment(id: String, accessToken: String) async throws -> ReservationHold {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/reservations/\(id)/resume"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await self.request(request, as: ReservationHold.self)
    }

    func reschedule(id: String, startAt: Date, accessToken: String) async throws -> RescheduledReservation {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/reservations/\(id)/reschedule"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "start_at": ISO8601DateFormatter().string(from: startAt)
        ])
        return try await self.request(request, as: RescheduledReservation.self)
    }

    func cancel(id: String, accessToken: String) async throws -> CancelledReservation {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/reservations/\(id)/cancel"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await self.request(request, as: CancelledReservation.self)
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await request(URLRequest(url: baseURL.appendingPathComponent(path)), as: type)
    }

    private func request<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReservationAPIError.invalidResponse }
        if http.statusCode == 409 {
            let detail = (try? JSONDecoder().decode(APIErrorBody.self, from: data).detail) ?? "This time is no longer available"
            reservationAPILog.warning("Reservation API conflict path=\(request.url?.path ?? "unknown", privacy: .public) detail=\(detail, privacy: .private)")
            if detail == "This time is no longer available" { throw ReservationAPIError.slotTaken }
            throw ReservationAPIError.server(detail)
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(APIErrorBody.self, from: data).detail) ?? "Booking service error (\(http.statusCode))."
            reservationAPILog.error("Reservation API failed path=\(request.url?.path ?? "unknown", privacy: .public) status=\(http.statusCode) detail=\(detail, privacy: .private)")
            throw ReservationAPIError.server(detail)
        }
        do { return try decoder.decode(type, from: data) }
        catch { throw ReservationAPIError.invalidResponse }
    }
}

private struct APIErrorBody: Decodable {
    let detail: String
}
