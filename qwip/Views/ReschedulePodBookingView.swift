import SwiftUI
import Supabase

struct ReschedulePodBookingView: View {
    let booking: MyPodReservation
    let onRescheduled: (RescheduledReservation) -> Void

    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var day = PodTime.today
    @State private var desiredTime: Date
    @State private var showTimePicker = false
    @State private var availability: ReservationAvailability?
    @State private var selectedStart: Date?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var showRescheduleSuccess = false
    @State private var completedCalendarEvent: ReservationCalendarEvent?
    @State private var presentedCalendarEvent: ReservationCalendarEvent?

    init(booking: MyPodReservation, onRescheduled: @escaping (RescheduledReservation) -> Void) {
        self.booking = booking
        self.onRescheduled = onRescheduled
        _desiredTime = State(initialValue: booking.startAt)
    }

    private var availableSlots: [ReservationSlot] {
        (availability?.slots ?? []).filter { slot in
            PodTime.minutesSinceMidnight(slot.startAt) >= 8 * 60 &&
            slot.durations.contains { $0.minutes == booking.durationMinutes }
        }
    }

    private var nearbySlots: [ReservationSlot] {
        PodTime.nearbySlots(availableSlots, desiredTime: desiredTime)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(booking.podLabel)
                        .font(.dmSans(24, weight: .bold))
                        .foregroundStyle(Color.brandPrimary)
                    Text("Choose a new start time for your \(booking.durationMinutes)-minute booking.")
                        .font(.dmSans(14))
                        .foregroundStyle(Color.brandMutedText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Date").font(.dmSans(17, weight: .semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(PodTime.bookableDays, id: \.self) { date in
                                let isSelected = PodTime.text(day, format: "yyyy-MM-dd") == PodTime.text(date, format: "yyyy-MM-dd")
                                Button { day = date } label: {
                                    Text(PodTime.dayLabel(date))
                                        .font(.dmSans(14, weight: .medium))
                                        .foregroundStyle(isSelected ? Color.brandSecondary : Color.brandPrimary)
                                        .padding(.horizontal, 15)
                                        .padding(.vertical, 12)
                                        .background(isSelected ? Color.brandPrimary : Color.brandSecondary,
                                                    in: RoundedRectangle(cornerRadius: 13))
                                        .overlay(RoundedRectangle(cornerRadius: 13)
                                            .strokeBorder(isSelected ? .clear : Color.brandBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 11) {
                    Text("Start time").font(.dmSans(17, weight: .semibold))
                    Button { showTimePicker = true } label: {
                        HStack {
                            Text("Around \(PodTime.text(desiredTime, format: "HH:mm"))")
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .font(.dmSans(15))
                        .foregroundStyle(Color.brandPrimary)
                        .padding(15)
                        .background(Color.brandSecondary, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.brandBorder))
                    }
                    .buttonStyle(.plain)

                    if isLoading {
                        ProgressView("Checking availability…")
                    } else if availableSlots.isEmpty {
                        Text("No times available for this duration on this date.")
                            .font(.dmSans(13))
                            .foregroundStyle(Color.brandMutedText)
                    } else {
                        Text("Nearest available 15-minute starts")
                            .font(.dmSans(12))
                            .foregroundStyle(Color.brandMutedText)
                        HStack(spacing: 9) {
                            ForEach(nearbySlots) { slot in
                                let isSelected = selectedStart == slot.startAt
                                Button { selectedStart = slot.startAt } label: {
                                    Text(PodTime.text(slot.startAt, format: "HH:mm"))
                                        .font(.dmSans(14, weight: .semibold))
                                        .foregroundStyle(Color.brandPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(isSelected ? Color.brandPrimary.opacity(0.12) : Color.brandSecondary,
                                                    in: RoundedRectangle(cornerRadius: 13))
                                        .overlay(RoundedRectangle(cornerRadius: 13)
                                            .stroke(isSelected ? Color.brandPrimary : Color.brandBorder,
                                                    lineWidth: isSelected ? 1.5 : 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Your change").font(.dmSans(17, weight: .semibold))
                    Text("Current: \(PodTime.text(booking.startAt, format: "EEE d MMM, HH:mm"))")
                    if let selectedStart {
                        Text("New: \(PodTime.text(selectedStart, format: "EEE d MMM, HH:mm"))")
                            .fontWeight(.semibold)
                    }
                    Text("No additional payment · \(PodTime.price(booking.amountPence)) already paid")
                        .font(.dmSans(12))
                        .foregroundStyle(Color.brandMutedText)
                }
                .font(.dmSans(14))
                .foregroundStyle(Color.brandPrimary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.brandSecondary, in: RoundedRectangle(cornerRadius: 15))

                if let error {
                    Text(error).font(.dmSans(13)).foregroundStyle(.red)
                }
                Button { Task { await save() } } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text("Confirm new time")
                    }
                    .font(.dmSans(16, weight: .semibold))
                    .foregroundStyle(Color.brandSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
                .background(Color.brandPrimary, in: Capsule())
                .disabled(isSaving || selectedStart == nil)
                .opacity(isSaving || selectedStart == nil ? 0.5 : 1)
                Text("We'll email your updated booking details. Your access code stays the same.")
                    .font(.dmSans(12))
                    .foregroundStyle(Color.brandMutedText)
            }
            .padding(20)
        }
        .background(Color.brandSecondary.ignoresSafeArea())
        .navigationTitle("Change time")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTimePicker) {
            VStack(spacing: 8) {
                HStack {
                    Text("Choose a start time").font(.dmSans(18, weight: .semibold))
                    Spacer()
                    Button("Done") { showTimePicker = false }.foregroundStyle(Color.brandPrimary)
                }
                DatePicker("Desired time", selection: $desiredTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .environment(\.timeZone, PodTime.london)
            }
            .padding(20)
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
        }
        .task(id: PodTime.text(day, format: "yyyy-MM-dd")) { await loadAvailability() }
        .onChange(of: desiredTime) { _, time in
            selectedStart = PodTime.closestStart(availableSlots, desiredTime: time)
        }
        .alert("Booking updated", isPresented: $showRescheduleSuccess) {
            Button("Add to Calendar") { presentedCalendarEvent = completedCalendarEvent }
            Button("Done") { dismiss() }
        } message: {
            Text("Add a calendar event for the new time. If you saved the old time, remove that event from your calendar.")
        }
        .sheet(item: $presentedCalendarEvent, onDismiss: { dismiss() }) {
            ReservationCalendarSheet(booking: $0)
        }
    }

    private func loadAvailability() async {
        isLoading = true
        error = nil
        selectedStart = nil
        do {
            guard let token = authService.session?.accessToken else {
                throw ReservationAPIError.server("Sign in to view available times.")
            }
            let response = try await ReservationAPIClient.shared.availability(
                podId: booking.podId, day: day, accessToken: token)
            guard !Task.isCancelled else { return }
            availability = response
            selectedStart = PodTime.closestStart(availableSlots, desiredTime: desiredTime)
        } catch {
            guard !Task.isCancelled else { return }
            availability = nil
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        guard let selectedStart, let token = authService.session?.accessToken else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let result = try await ReservationAPIClient.shared.reschedule(
                id: booking.id, startAt: selectedStart, accessToken: token)
            await ReservationReminderService.update(id: booking.id, podLabel: booking.podLabel,
                                                    startAt: result.startAt, endAt: result.endAt)
            onRescheduled(result)
            completedCalendarEvent = ReservationCalendarEvent(booking: booking, rescheduled: result)
            showRescheduleSuccess = true
        } catch ReservationAPIError.slotTaken {
            await loadAvailability()
            error = ReservationAPIError.slotTaken.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}
