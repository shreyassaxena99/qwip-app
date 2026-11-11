import SwiftUI
import EventKit
import EventKitUI

struct ReservationCalendarEvent: Identifiable {
    let id: String
    let podLabel: String
    let startAt: Date
    let endAt: Date

    init(booking: MyPodReservation) {
        id = booking.id
        podLabel = booking.podLabel
        startAt = booking.startAt
        endAt = booking.endAt
    }

    init(booking: MyPodReservation, rescheduled: RescheduledReservation) {
        id = booking.id
        podLabel = booking.podLabel
        startAt = rescheduled.startAt
        endAt = rescheduled.endAt
    }
}

struct ReservationCalendarSheet: View {
    let booking: ReservationCalendarEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        EventEditor(booking: booking) { dismiss() }
    }
}

private struct EventEditor: UIViewControllerRepresentable {
    let booking: ReservationCalendarEvent
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "qwip pod booking · \(booking.podLabel)"
        event.startDate = booking.startAt
        event.endDate = booking.endAt
        event.timeZone = TimeZone(identifier: "Europe/London")
        event.location = booking.podLabel
        event.notes = "Booking reference: \(booking.id)"

        let editor = EKEventEditViewController()
        editor.eventStore = store
        editor.event = event
        editor.editViewDelegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            onFinish()
        }
    }
}
