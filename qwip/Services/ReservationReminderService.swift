import Foundation
import UserNotifications

enum ReservationReminderService {
    private static let startPrefix = "reservation-start-"
    private static let endPrefix = "reservation-end-"
    private static let legacyPrefix = "reservation-one-hour-"
    private static let startLeadTime: TimeInterval = 15 * 60
    private static let endLeadTime: TimeInterval = 5 * 60

    static func sync(_ bookings: [MyPodReservation]) async {
        let center = UNUserNotificationCenter.current()
        let confirmed = bookings.filter { $0.status == "paid" || $0.status == "confirmed" }
        let wanted = Set(confirmed.flatMap { booking in
            [
                booking.startAt.addingTimeInterval(-startLeadTime) > .now ? startPrefix + booking.id : nil,
                booking.endAt.addingTimeInterval(-endLeadTime) > .now ? endPrefix + booking.id : nil
            ].compactMap { $0 }
        })
        let pending = await center.pendingNotificationRequests()
        let obsolete = pending.map(\.identifier).filter { id in
            id.hasPrefix(legacyPrefix) ||
            ((id.hasPrefix(startPrefix) || id.hasPrefix(endPrefix)) && !wanted.contains(id))
        }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)

        guard !wanted.isEmpty, await notificationsAllowed(center) else { return }
        for booking in confirmed {
            if wanted.contains(startPrefix + booking.id) {
                try? await center.add(request(id: startPrefix + booking.id,
                                              bookingId: booking.id,
                                              title: "Your qwip booking starts in 15 minutes",
                                              body: "Tap for your booking details at \(booking.podLabel).",
                                              at: booking.startAt.addingTimeInterval(-startLeadTime)))
            }
            if wanted.contains(endPrefix + booking.id) {
                try? await center.add(request(id: endPrefix + booking.id,
                                              bookingId: booking.id,
                                              title: "Your qwip booking ends in 5 minutes",
                                              body: "Please leave the pod tidy. Tap to view your booking details.",
                                              at: booking.endAt.addingTimeInterval(-endLeadTime)))
            }
        }
    }

    static func update(id: String, podLabel: String, startAt: Date, endAt: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            legacyPrefix + id, startPrefix + id, endPrefix + id
        ])
        guard await notificationsAllowed(center) else { return }
        if startAt.addingTimeInterval(-startLeadTime) > .now {
            try? await center.add(request(id: startPrefix + id, bookingId: id,
                                          title: "Your qwip booking starts in 15 minutes",
                                          body: "Tap for your booking details at \(podLabel).",
                                          at: startAt.addingTimeInterval(-startLeadTime)))
        }
        if endAt.addingTimeInterval(-endLeadTime) > .now {
            try? await center.add(request(id: endPrefix + id, bookingId: id,
                                          title: "Your qwip booking ends in 5 minutes",
                                          body: "Please leave the pod tidy. Tap to view your booking details.",
                                          at: endAt.addingTimeInterval(-endLeadTime)))
        }
    }

    private static func request(id: String, bookingId: String, title: String,
                                body: String, at date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["reservation_id": bookingId]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(identifier: id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components,
                                                                            repeats: false))
    }

    private static func notificationsAllowed(_ center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        default:
            return false
        }
    }
}

@MainActor
final class ReservationNotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReservationNotificationHandler()
    private weak var router: AppRouter?
    private var pendingBookingId: String?

    func connect(to router: AppRouter) {
        self.router = router
        if let pendingBookingId {
            router.pendingBookingId = pendingBookingId
            self.pendingBookingId = nil
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["reservation_id"] as? String else { return }
        await MainActor.run {
            if let router { router.pendingBookingId = id }
            else { pendingBookingId = id }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
