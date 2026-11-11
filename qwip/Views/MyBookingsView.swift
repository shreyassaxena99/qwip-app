import SwiftUI
import StripePaymentSheet
import Supabase
import UIKit

struct MyBookingsView: View {
    @Environment(AuthService.self) private var authService
    @State private var bookings: [MyPodReservation] = []
    @State private var isLoading = true
    @State private var error: String?

    private var upcoming: [MyPodReservation] {
        bookings.filter(\.isUpcoming).sorted { $0.startAt < $1.startAt }
    }

    private var current: [MyPodReservation] {
        bookings.filter(\.isCurrent).sorted { $0.startAt < $1.startAt }
    }

    private var history: [MyPodReservation] {
        bookings.filter { !$0.isCurrent && !$0.isUpcoming }.sorted { $0.startAt > $1.startAt }
    }

    var body: some View {
        Group {
            if isLoading && bookings.isEmpty {
                ProgressView("Loading bookings…")
            } else if let error, bookings.isEmpty {
                ContentUnavailableView("Couldn't load bookings", systemImage: "wifi.exclamationmark",
                                       description: Text(error))
                    .overlay(alignment: .bottom) {
                        Button("Try again") { Task { await load() } }
                            .padding(.bottom, 80)
                    }
            } else if bookings.isEmpty {
                ContentUnavailableView("No bookings yet", systemImage: "calendar",
                                       description: Text("Your pod reservations will appear here."))
            } else {
                List {
                    if let error {
                        Section { Text(error).foregroundStyle(.red) }
                    }
                    if !current.isEmpty {
                        Section("Current") {
                            ForEach(current) { booking in
                                NavigationLink {
                                    MyBookingDetailView(booking: booking) { Task { await load() } }
                                } label: {
                                    bookingRow(booking)
                                }
                            }
                        }
                    }
                    if !upcoming.isEmpty {
                        Section("Upcoming") {
                            ForEach(upcoming) { booking in
                                NavigationLink {
                                    MyBookingDetailView(booking: booking) { Task { await load() } }
                                } label: {
                                    bookingRow(booking)
                                }
                            }
                        }
                    }
                    if !history.isEmpty {
                        Section("Past & other") {
                            ForEach(history) { booking in
                                NavigationLink {
                                    MyBookingDetailView(booking: booking) { Task { await load() } }
                                } label: {
                                    bookingRow(booking)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandSecondary.ignoresSafeArea())
        .navigationTitle("My Bookings")
        .navigationBarTitleDisplayMode(.large)
        .task(id: authService.session?.user.id) { await load() }
        .refreshable { await load() }
    }

    private func bookingRow(_ booking: MyPodReservation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(booking.podLabel).font(.dmSans(16, weight: .bold))
                .foregroundStyle(Color.brandPrimary)
            Text(PodTime.text(booking.startAt, format: "EEE d MMM yyyy, h:mm a"))
                .font(.dmSans(13)).foregroundStyle(Color.brandMutedText)
            Text(booking.statusTitle)
                .font(.dmSans(12, weight: .semibold))
                .foregroundStyle(booking.status == "paid" || booking.status == "confirmed"
                                 ? Color.brandPrimary : Color.secondary)
        }
        .padding(.vertical, 5)
    }

    private func load() async {
        guard let session = authService.session else {
            bookings = []
            await ReservationReminderService.sync([])
            isLoading = false
            error = "Sign in to view your bookings."
            return
        }
        isLoading = true
        error = nil
        do {
            bookings = try await ReservationAPIClient.shared.myBookings(accessToken: session.accessToken)
            await ReservationReminderService.sync(bookings)
        }
        catch { self.error = error.localizedDescription }
        isLoading = false
    }
}

struct MyBookingDetailView: View {
    @State private var booking: MyPodReservation
    @State private var calendarEvent: ReservationCalendarEvent?
    @State private var paymentSheet: PaymentSheet?
    @State private var showPaymentSheet = false
    @State private var paymentPresentationID: UUID?
    @State private var isResumingPayment = false
    @State private var resumeUnavailable = false
    @State private var paymentError: String?
    @State private var showPaymentStatus = false
    @State private var showCancelConfirmation = false
    @State private var isCancelling = false
    @State private var cancellationError: String?
    @State private var cancellationMessage: String?
    @State private var accessCode: String?
    @State private var accessCodeError: String?
    @State private var isLoadingAccessCode = false
    @State private var podAddress: String?
    @State private var capturedCheckInPhoto: UIImage?
    @State private var checkInUploadedAt: Date?
    @State private var isUploadingCheckIn = false
    @State private var checkInError: String?
    @State private var showCheckInCamera = false
    @State private var showCameraUnavailable = false
    @State private var now = Date.now
    @Environment(AuthService.self) private var authService
    let onRescheduled: () -> Void

    init(booking: MyPodReservation, onRescheduled: @escaping () -> Void) {
        _booking = State(initialValue: booking)
        self.onRescheduled = onRescheduled
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(booking.podLabel).font(.dmSans(24, weight: .bold))
                    Text(booking.statusTitle)
                        .font(.dmSans(14, weight: .semibold))
                        .foregroundStyle(booking.status == "paid" || booking.status == "confirmed"
                                         ? Color.brandPrimary : Color.secondary)
                }
                .foregroundStyle(Color.brandPrimary)

                VStack(spacing: 14) {
                    detail("Date", PodTime.text(booking.startAt, format: "EEEE d MMMM yyyy"))
                    Divider()
                    detail("Time", "\(PodTime.text(booking.startAt, format: "h:mm a")) – \(PodTime.text(booking.endAt, format: "h:mm a"))")
                    Divider()
                    detail("Duration", booking.durationMinutes % 60 == 0
                           ? "\(booking.durationMinutes / 60) hour\(booking.durationMinutes == 60 ? "" : "s")"
                           : "\(booking.durationMinutes / 60)h \(booking.durationMinutes % 60)m")
                    Divider()
                    detail("Amount", PodTime.price(booking.amountPence))
                }
                .padding(18)
                .background(Color.brandSecondary, in: RoundedRectangle(cornerRadius: 18))

                if booking.status == "paid" || booking.status == "confirmed" {
                    if booking.endAt > now {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pod access code")
                                .font(.dmSans(14, weight: .semibold))
                            if let accessCode {
                                Text(accessCode)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .textSelection(.enabled)
                                    .accessibilityLabel("Pod access code \(accessCode)")
                            } else if isLoadingAccessCode {
                                ProgressView("Loading access code…")
                            } else {
                                Text(accessCodeError ?? "Your access code will appear here when it is ready.")
                                    .font(.dmSans(13))
                                    .foregroundStyle(Color.brandMutedText)
                                Button("Try again") { Task { await loadAccessCode() } }
                                    .font(.dmSans(13, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Color.brandSecondary, in: RoundedRectangle(cornerRadius: 18))
                    }
                    if let podAddress, let directionsURL {
                        Link(destination: directionsURL) {
                            Label("Get directions", systemImage: "map")
                                .font(.dmSans(15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.brandPrimary)
                        Text(podAddress)
                            .font(.dmSans(12))
                            .foregroundStyle(Color.brandMutedText)
                    }
                    if let uploadedAt = checkInUploadedAt ?? booking.checkInPhotoUploadedAt {
                        Label("Checked in with a photo at \(PodTime.text(uploadedAt, format: "h:mm a"))",
                              systemImage: "checkmark.circle.fill")
                            .font(.dmSans(14, weight: .semibold))
                            .foregroundStyle(Color.brandPrimary)
                    } else if booking.startAt.addingTimeInterval(-15 * 60) <= now && booking.endAt > now {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Check in")
                                .font(.dmSans(18, weight: .bold))
                            Text("Take a photo of the pod as you find it, before you settle in. Your access code is available above whether or not you check in.")
                                .font(.dmSans(13))
                                .foregroundStyle(Color.brandMutedText)
                            if let photo = capturedCheckInPhoto {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Button("Retake photo") { openCheckInCamera() }
                                    .disabled(isUploadingCheckIn)
                                Button {
                                    Task { await uploadCheckInPhoto(photo) }
                                } label: {
                                    HStack {
                                        if isUploadingCheckIn { ProgressView().tint(.white) }
                                        Text("Use photo and check in")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.brandPrimary)
                                .disabled(isUploadingCheckIn)
                            } else {
                                Button { openCheckInCamera() } label: {
                                    Label("Take check-in photo", systemImage: "camera")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.brandPrimary)
                            }
                            if let checkInError {
                                Text(checkInError).font(.dmSans(13)).foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Color.brandSecondary, in: RoundedRectangle(cornerRadius: 18))
                    }
                    Button {
                        calendarEvent = ReservationCalendarEvent(booking: booking)
                    } label: {
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                            .font(.dmSans(15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.brandPrimary)
                }
                if booking.canContinuePayment && !resumeUnavailable {
                    Button {
                        Task { await resumePayment() }
                    } label: {
                        HStack {
                            if isResumingPayment { ProgressView().tint(Color.brandSecondary) }
                            Label("Continue payment", systemImage: "creditcard")
                        }
                        .font(.dmSans(15, weight: .semibold))
                        .foregroundStyle(Color.brandSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brandPrimary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isResumingPayment)
                    if let holdExpiresAt = booking.holdExpiresAt {
                        Text("Complete payment before \(PodTime.text(holdExpiresAt, format: "h:mm a")) to keep this time.")
                            .font(.dmSans(12))
                            .foregroundStyle(Color.brandMutedText)
                    }
                }
                if let paymentError {
                    Text(paymentError).font(.dmSans(13)).foregroundStyle(.red)
                }
                if booking.canReschedule {
                    NavigationLink {
                        ReschedulePodBookingView(booking: booking) { result in
                            booking = MyPodReservation(
                                id: booking.id, podId: booking.podId, podLabel: booking.podLabel,
                                startAt: result.startAt, endAt: result.endAt,
                                durationMinutes: booking.durationMinutes, amountPence: booking.amountPence,
                                status: booking.status, holdExpiresAt: booking.holdExpiresAt,
                                codeEmailed: booking.codeEmailed,
                                customerCancelRequestedAt: booking.customerCancelRequestedAt,
                                refundStatus: booking.refundStatus,
                                checkInPhotoUploadedAt: booking.checkInPhotoUploadedAt
                            )
                            onRescheduled()
                        }
                    } label: {
                        Label("Change time", systemImage: "calendar")
                            .font(.dmSans(15, weight: .semibold))
                            .foregroundStyle(Color.brandSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.brandPrimary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Text("You can change the time until one hour before your booking starts. The pod, duration and price stay the same.")
                        .font(.dmSans(12))
                        .foregroundStyle(Color.brandMutedText)
                }
                if booking.canCancel {
                    Button(role: .destructive) { showCancelConfirmation = true } label: {
                        Label("Cancel booking", systemImage: "xmark.circle")
                            .font(.dmSans(15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCancelling)
                    Text("Cancel until one hour before your booking starts for a full refund to your original payment method.")
                        .font(.dmSans(12))
                        .foregroundStyle(Color.brandMutedText)
                }
                if booking.canRetryRefund {
                    Button { Task { await cancelBooking() } } label: {
                        HStack {
                            if isCancelling { ProgressView() }
                            Text("Retry refund")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCancelling)
                }
                if booking.status == "cancelled" && booking.refundStatus == "failed" {
                    Text("The refund failed. Please contact Qwip support with your booking reference.")
                        .font(.dmSans(13))
                        .foregroundStyle(.red)
                }
                if let cancellationMessage {
                    Text(cancellationMessage).font(.dmSans(13)).foregroundStyle(Color.brandMutedText)
                }
                if let cancellationError {
                    Text(cancellationError).font(.dmSans(13)).foregroundStyle(.red)
                }
                Text("Booking reference: \(booking.id)")
                    .font(.dmSans(12))
                    .foregroundStyle(Color.brandMutedText)
                    .textSelection(.enabled)
            }
            .padding(20)
        }
        .background(Color.brandSecondary.ignoresSafeArea())
        .navigationTitle("Booking details")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Cancel this booking?", isPresented: $showCancelConfirmation,
                            titleVisibility: .visible) {
            Button("Cancel booking and refund \(PodTime.price(booking.amountPence))", role: .destructive) {
                Task { await cancelBooking() }
            }
        } message: {
            Text("Your pod time will be released immediately. The full refund will go to your original payment method.")
        }
        .sheet(item: $calendarEvent) { ReservationCalendarSheet(booking: $0) }
        .fullScreenCover(isPresented: $showCheckInCamera) {
            ReservationCheckInCamera(onPhoto: { photo in
                capturedCheckInPhoto = photo
                checkInError = nil
                showCheckInCamera = false
            }, onCancel: {
                showCheckInCamera = false
            })
            .ignoresSafeArea()
        }
        .alert("Camera unavailable", isPresented: $showCameraUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A camera is needed for the check-in photo. You can still use your access code.")
        }
        .task(id: booking.id) {
            await loadAccessCode()
            await loadPodAddress()
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
                now = .now
            }
        }
        .modifier(BookingPaymentModifier(paymentSheet: paymentSheet,
                                         isPresented: $showPaymentSheet,
                                         onCompletion: handlePaymentResult))
        .task(id: paymentPresentationID) {
            guard paymentPresentationID != nil, paymentSheet != nil else { return }
            showPaymentSheet = true
        }
        .navigationDestination(isPresented: $showPaymentStatus) {
            PodReservationStatusView(reservationId: booking.id)
        }
        .onChange(of: showPaymentStatus) { wasShowing, isShowing in
            if wasShowing && !isShowing { Task { await refreshBooking() } }
        }
        .task(id: booking.holdExpiresAt) {
            guard booking.status == "pending", let expiresAt = booking.holdExpiresAt else { return }
            let remaining = expiresAt.timeIntervalSinceNow
            if remaining > 0 {
                do { try await Task.sleep(for: .seconds(remaining)) }
                catch { return }
            }
            guard booking.status == "pending" else { return }
            resumeUnavailable = true
            paymentError = "This payment hold has expired. Please choose a time again."
            onRescheduled()
        }
    }

    private var directionsURL: URL? {
        guard let podAddress else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.queryItems = [URLQueryItem(name: "daddr", value: podAddress)]
        return components.url
    }

    private func loadAccessCode() async {
        guard (booking.status == "paid" || booking.status == "confirmed"),
              booking.endAt > .now,
              let token = authService.session?.accessToken else { return }
        isLoadingAccessCode = true
        accessCodeError = nil
        defer { isLoadingAccessCode = false }
        do {
            accessCode = try await ReservationAPIClient.shared.accessCode(
                id: booking.id, accessToken: token).accessCode
        } catch {
            accessCodeError = error.localizedDescription
        }
    }

    private func loadPodAddress() async {
        guard let token = authService.session?.accessToken else { return }
        do {
            podAddress = try await ReservationAPIClient.shared.pods(accessToken: token)
                .first(where: { $0.id == booking.podId })?.address
        } catch {
            podAddress = nil
        }
    }

    private func openCheckInCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showCameraUnavailable = true
            return
        }
        showCheckInCamera = true
    }

    private func uploadCheckInPhoto(_ photo: UIImage) async {
        guard let token = authService.session?.accessToken else {
            checkInError = "Sign in to upload your check-in photo."
            return
        }
        let scale = min(1, 2000 / max(photo.size.width, photo.size.height))
        let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in photo.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpegData = resized.jpegData(compressionQuality: 0.8),
              jpegData.count <= 10 * 1024 * 1024 else {
            checkInError = "This photo is too large. Please retake it."
            return
        }
        isUploadingCheckIn = true
        checkInError = nil
        defer { isUploadingCheckIn = false }
        do {
            let result = try await ReservationAPIClient.shared.uploadCheckInPhoto(
                id: booking.id, jpegData: jpegData, accessToken: token)
            checkInUploadedAt = result.checkInPhotoUploadedAt
            capturedCheckInPhoto = nil
            await refreshBooking()
        } catch {
            checkInError = error.localizedDescription
        }
    }

    private func resumePayment() async {
        guard let token = authService.session?.accessToken else { return }
        paymentError = nil
        isResumingPayment = true
        defer { isResumingPayment = false }
        do {
            let hold = try await ReservationAPIClient.shared.resumePayment(id: booking.id,
                                                                            accessToken: token)
            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "Qwip"
            configuration.returnURL = "qwip://stripe-redirect"
            configuration.allowsDelayedPaymentMethods = false
            paymentSheet = PaymentSheet(paymentIntentClientSecret: hold.clientSecret,
                                        configuration: configuration)
            paymentPresentationID = UUID()
        } catch {
            paymentError = error.localizedDescription
            if case ReservationAPIError.server(let message) = error,
               message.contains("expired") || message.contains("processing") {
                resumeUnavailable = true
            }
            onRescheduled()
        }
    }

    private func refreshBooking() async {
        if let token = authService.session?.accessToken,
           let latest = try? await ReservationAPIClient.shared.myBookings(accessToken: token),
           let updated = latest.first(where: { $0.id == booking.id }) {
            booking = updated
            if updated.status != "paid" && updated.status != "confirmed" { accessCode = nil }
            else if accessCode == nil { await loadAccessCode() }
        }
        onRescheduled()
    }

    private func cancelBooking() async {
        guard let token = authService.session?.accessToken else {
            cancellationError = "Sign in to cancel this booking."
            return
        }
        isCancelling = true
        cancellationError = nil
        cancellationMessage = nil
        defer { isCancelling = false }
        do {
            let result = try await ReservationAPIClient.shared.cancel(id: booking.id, accessToken: token)
            cancellationMessage = result.refundIssued
                ? "Booking cancelled. Your refund has been requested from Stripe."
                : "Booking cancelled. Please contact Qwip support about your refund."
        } catch {
            cancellationError = error.localizedDescription
        }
        await refreshBooking()
    }

    private func handlePaymentResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            showPaymentStatus = true
        case .failed(let error):
            paymentError = error.localizedDescription
        case .canceled:
            break
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(Color.brandMutedText)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(Color.brandPrimary).multilineTextAlignment(.trailing)
        }
        .font(.dmSans(14))
    }
}
