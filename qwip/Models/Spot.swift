import Foundation
import CoreLocation

// MARK: - Enums

enum SpotCategory: String, CaseIterable, Codable, Identifiable {
    case cafe = "cafe"
    case coworking = "coworking"
    case gym = "gym"
    case hotelLobby = "hotel_lobby"
    case library = "library"
    case restaurant = "restaurant"
    case pod = "pod"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cafe: return "Cafe"
        case .coworking: return "Coworking"
        case .gym: return "Gym"
        case .hotelLobby: return "Hotel"
        case .library: return "Library"
        case .restaurant: return "Restaurant"
        case .pod: return "Pod"
        case .other: return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .cafe: return "ic_coffee"
        case .coworking: return "ic_laptop_2"
        case .gym: return "ic_dumbbell"
        case .hotelLobby: return "ic_hotel"
        case .library: return "ic_book_open"
        case .restaurant: return "ic_utensils"
        case .pod: return "ic_pod_door"
        case .other: return "ic_map_pin"
        }
    }
}

enum AccessType: String, Codable {
    case free = "free"
    case purchaseRequired = "purchase_required"
    case membersOnly = "members_only"

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .purchaseRequired: return "Buy Something"
        case .membersOnly: return "Members Only"
        }
    }

    var iconName: String {
        switch self {
        case .free: return "ic_check_circle"
        case .purchaseRequired: return "ic_credit_card"
        case .membersOnly: return "ic_key_round"
        }
    }
}

enum NoiseLevel: String, Codable {
    case quiet = "quiet"
    case moderate = "moderate"
    case lively = "lively"

    var displayName: String {
        switch self {
        case .quiet: return "Quiet"
        case .moderate: return "Moderate"
        case .lively: return "Lively"
        }
    }

    var iconName: String {
        switch self {
        case .quiet: return "ic_volume_x"
        case .moderate: return "ic_volume_1"
        case .lively: return "ic_volume_2"
        }
    }
}

// MARK: - Noise Matrix

struct NoiseCell: Codable {
    let level: String?
    let updatedAt: String?

    var noiseLevel: NoiseLevel? { level.flatMap(NoiseLevel.init) }
}

struct NoiseDayMatrix: Codable {
    let morning: NoiseCell
    let afternoon: NoiseCell
    let evening: NoiseCell
}

struct NoiseMatrix: Codable {
    let weekday: NoiseDayMatrix
    let weekend: NoiseDayMatrix

    func currentLevel(at date: Date = .now) -> NoiseLevel? {
        currentCell(at: date).noiseLevel
    }

    /// "Usually quiet on weekday mornings"
    func currentDisplayText(at date: Date = .now) -> String? {
        guard let level = currentLevel(at: date) else { return nil }
        let (dayType, timeOfDay) = Self.currentPeriodDescription(at: date)
        return "Usually \(level.displayName.lowercased()) on \(dayType) \(timeOfDay)"
    }

    private func currentCell(at date: Date) -> NoiseCell {
        let cal = Calendar.current
        let isWeekend = cal.isDateInWeekend(date)
        let hour = cal.component(.hour, from: date)
        let dayMatrix = isWeekend ? weekend : weekday
        switch hour {
        case 6...10: return dayMatrix.morning
        case 11...15: return dayMatrix.afternoon
        default:     return dayMatrix.evening
        }
    }

    static func currentPeriodDescription(at date: Date = .now) -> (dayType: String, timeOfDay: String) {
        let cal = Calendar.current
        let isWeekend = cal.isDateInWeekend(date)
        let hour = cal.component(.hour, from: date)
        let dayType = isWeekend ? "weekends" : "weekdays"
        let timeOfDay: String
        switch hour {
        case 6...10: timeOfDay = "mornings"
        case 11...15: timeOfDay = "afternoons"
        default:     timeOfDay = "evenings"
        }
        return (dayType, timeOfDay)
    }
}

// MARK: - SpotPin  (GET /spots list item)

struct SpotPin: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let shortAddress: String?
    let latitude: Double
    let longitude: Double
    let category: SpotCategory
    let accessType: AccessType
    let wifiAvailable: Bool
    let powerOutlets: Bool
    let noiseMatrix: NoiseMatrix?
    let rating: Double?
    let isOpenNow: Bool?
    let isInUse: Bool?
    let podId: String?
    let coverPhoto: String?

    enum CodingKeys: String, CodingKey {
        case id, name, shortAddress, latitude, longitude
        case category, accessType, wifiAvailable, powerOutlets
        case noiseMatrix, rating, isOpenNow, isInUse, podId, coverPhoto
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var formattedRating: String {
        guard let r = rating else { return "–" }
        return String(format: "%.1f", r)
    }

    static func == (lhs: SpotPin, rhs: SpotPin) -> Bool { lhs.id == rhs.id }
}

// MARK: - SpotDetail  (GET /spots/{id} full detail)

struct SpotDetail: Identifiable, Codable {
    let id: String
    let name: String
    let shortAddress: String?
    let latitude: Double
    let longitude: Double
    let category: SpotCategory
    let accessType: AccessType
    let wifiAvailable: Bool
    let powerOutlets: Bool
    let noiseMatrix: NoiseMatrix?
    let rating: Double?
    let isOpenNow: Bool?
    let isInUse: Bool?
    let podId: String?
    let coverPhoto: String?

    // Detail-only
    let formattedAddress: String?
    let phoneNational: String?
    let googleMapsUri: String?
    let websiteUri: String?
    let userRatingCount: Int?
    let editorialSummary: String?
    let businessStatus: String?
    let outdoorSeating: Bool?
    let restroom: Bool?
    let servesCoffee: Bool?
    let allowsDogs: Bool?
    let goodForGroups: Bool?
    let description: String?
    let photos: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, shortAddress, latitude, longitude
        case category, accessType, wifiAvailable, powerOutlets
        case rating, isOpenNow, isInUse, podId, coverPhoto
        case noiseMatrix
        case formattedAddress, phoneNational, googleMapsUri, websiteUri
        case userRatingCount, editorialSummary, businessStatus
        case outdoorSeating, restroom, servesCoffee, allowsDogs, goodForGroups
        case description, photos
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        shortAddress = try c.decodeIfPresent(String.self, forKey: .shortAddress)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        category = try c.decode(SpotCategory.self, forKey: .category)
        accessType = try c.decode(AccessType.self, forKey: .accessType)
        wifiAvailable = try c.decode(Bool.self, forKey: .wifiAvailable)
        powerOutlets = try c.decode(Bool.self, forKey: .powerOutlets)
        noiseMatrix = try c.decodeIfPresent(NoiseMatrix.self, forKey: .noiseMatrix)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        isOpenNow = try c.decodeIfPresent(Bool.self, forKey: .isOpenNow)
        isInUse = try c.decodeIfPresent(Bool.self, forKey: .isInUse)
        podId = try c.decodeIfPresent(String.self, forKey: .podId)
        coverPhoto = try c.decodeIfPresent(String.self, forKey: .coverPhoto)
        formattedAddress = try c.decodeIfPresent(String.self, forKey: .formattedAddress)
        phoneNational = try c.decodeIfPresent(String.self, forKey: .phoneNational)
        googleMapsUri = try c.decodeIfPresent(String.self, forKey: .googleMapsUri)
        websiteUri = try c.decodeIfPresent(String.self, forKey: .websiteUri)
        userRatingCount = try c.decodeIfPresent(Int.self, forKey: .userRatingCount)
        editorialSummary = try c.decodeIfPresent(String.self, forKey: .editorialSummary)
        businessStatus = try c.decodeIfPresent(String.self, forKey: .businessStatus)
        outdoorSeating = try c.decodeIfPresent(Bool.self, forKey: .outdoorSeating)
        restroom = try c.decodeIfPresent(Bool.self, forKey: .restroom)
        servesCoffee = try c.decodeIfPresent(Bool.self, forKey: .servesCoffee)
        allowsDogs = try c.decodeIfPresent(Bool.self, forKey: .allowsDogs)
        goodForGroups = try c.decodeIfPresent(Bool.self, forKey: .goodForGroups)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        photos = (try? c.decodeIfPresent([String].self, forKey: .photos)) ?? []
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayAddress: String? { formattedAddress ?? shortAddress }
    var displayDescription: String? { editorialSummary ?? description }

    /// Converts this detail record to the lighter SpotPin type,
    /// used to construct optimistic SavedSpotEntry stubs without a network call.
    var asSpotPin: SpotPin {
        SpotPin(
            id: id,
            name: name,
            shortAddress: shortAddress,
            latitude: latitude,
            longitude: longitude,
            category: category,
            accessType: accessType,
            wifiAvailable: wifiAvailable,
            powerOutlets: powerOutlets,
            noiseMatrix: noiseMatrix,
            rating: rating,
            isOpenNow: isOpenNow,
            isInUse: isInUse,
            podId: podId,
            coverPhoto: coverPhoto
        )
    }

    var formattedRating: String {
        guard let r = rating else { return "–" }
        return String(format: "%.1f", r)
    }

    var hasAmenities: Bool {
        (outdoorSeating == true) || (allowsDogs == true) ||
        (servesCoffee == true) || (goodForGroups == true)
    }
}

// MARK: - SavedSpotEntry  (GET /me/saved-spots item)

struct SavedSpotEntry: Identifiable, Codable {
    let spot: SpotPin
    let savedAt: Date
    let collectionIds: [String]

    /// Stable identity uses the nested spot's ID.
    var id: String { spot.id }
}
