import Foundation

struct ReservablePod: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let address: String
}

struct PodListResponse: Decodable {
    let pods: [ReservablePod]
}

struct ReservationAvailability: Decodable {
    let date: String
    let slots: [ReservationSlot]
}

struct ReservationSlot: Decodable, Identifiable, Hashable {
    let startAt: Date
    let durations: [ReservationDuration]
    var id: Date { startAt }
}

struct ReservationDuration: Decodable, Hashable {
    let minutes: Int
    let amountPence: Int
}

struct ReservationHold: Decodable {
    let reservationId: String
    let clientSecret: String
    let amountPence: Int
    let currency: String
    let holdExpiresAt: Date
}

struct ReservationStatus: Decodable {
    let status: String
    let codeEmailed: Bool

    var isConfirmed: Bool { status == "paid" || status == "confirmed" }
    var isTerminalFailure: Bool {
        ["expired", "refunded", "cancelled", "failed"].contains(status)
    }
}

struct MyReservationsResponse: Decodable {
    let bookings: [MyPodReservation]
}

struct MyPodReservation: Decodable, Identifiable {
    let id: String
    let podId: String
    let podLabel: String
    let startAt: Date
    let endAt: Date
    let durationMinutes: Int
    let amountPence: Int
    let status: String
    let holdExpiresAt: Date?
    let codeEmailed: Bool
    let customerCancelRequestedAt: Date?
    let refundStatus: String?
    let checkInPhotoUploadedAt: Date?

    var canCheckIn: Bool {
        (status == "paid" || status == "confirmed") &&
        startAt.addingTimeInterval(-15 * 60) <= .now && endAt > .now &&
        checkInPhotoUploadedAt == nil
    }

    var canContinuePayment: Bool {
        status == "pending" && (holdExpiresAt.map { $0 > .now } ?? false)
    }

    var canReschedule: Bool {
        status == "paid" && startAt > Date.now.addingTimeInterval(60 * 60)
    }

    var canCancel: Bool {
        status == "paid" && startAt > Date.now.addingTimeInterval(60 * 60)
    }

    var canRetryRefund: Bool {
        status == "cancelled" && customerCancelRequestedAt != nil && refundStatus == nil
    }

    var isUpcoming: Bool {
        startAt > .now && (status == "paid" || status == "confirmed" || status == "pending")
    }

    var isCurrent: Bool {
        startAt <= .now && endAt > .now && (status == "paid" || status == "confirmed")
    }

    var statusTitle: String {
        switch status {
        case "paid", "confirmed": return isCurrent ? "In progress" : "Confirmed"
        case "pending": return "Awaiting payment"
        case "expired": return "Expired"
        case "refunded": return "Refunded"
        case "cancelled":
            if customerCancelRequestedAt != nil {
                switch refundStatus {
                case "succeeded": return "Cancelled · refunded"
                case "pending", "requires_action": return "Cancelled · refund pending"
                case "failed": return "Cancelled · refund needs help"
                default: return "Cancelled · refund unconfirmed"
                }
            }
            return "Cancelled"
        case "failed": return "Payment failed"
        default: return status.capitalized
        }
    }
}

struct RescheduledReservation: Decodable {
    let status: String
    let reservationId: String
    let startAt: Date
    let endAt: Date
}

struct CancelledReservation: Decodable {
    let status: String
    let refundStatus: String
    let refundIssued: Bool
}

struct ReservationAccessCode: Decodable {
    let accessCode: String
}

struct ReservationCheckInPhoto: Decodable {
    let checkInPhotoUploadedAt: Date
}
