import SwiftUI
import StripePaymentSheet
import Supabase
import OSLog

private let reservationLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "qwip",
                                    category: "ReservationCheckout")

private struct NotificationBookingRoute: Hashable, Identifiable {
    let id: String
}

private func checkoutDiagnostic(_ error: Error) -> String {
    var parts = ["swiftType=\(String(reflecting: type(of: error)))"]
    var current: NSError? = error as NSError
    for level in 0..<3 {
        guard let failure = current else { break }
        parts.append("level\(level) domain=\(failure.domain) code=\(failure.code) message=\(failure.localizedDescription)")
        let stripeFields = [
            "stripeCode": "com.stripe.lib:StripeErrorCodeKey",
            "stripeType": "com.stripe.lib:StripeErrorTypeKey",
            "declineCode": "com.stripe.lib:DeclineCodeKey",
            "requestID": "com.stripe.lib:StripeRequestIDKey",
        ]
        for (label, key) in stripeFields {
            if let value = failure.userInfo[key] as? String {
                parts.append("\(label)=\(value)")
            }
        }
        if let httpStatus = failure.userInfo["com.stripe.lib:HTTPStatusCodeKey"] as? Int {
            parts.append("stripeHTTP=\(httpStatus)")
        }
        current = (failure.userInfo[NSUnderlyingErrorKey] as? Error).map { $0 as NSError }
    }
    return parts.joined(separator: " | ")
}

enum PodTime {
    static let london = TimeZone(identifier: "Europe/London")!
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        return calendar
    }
    static var today: Date { calendar.startOfDay(for: .now) }
    static var bookableDays: [Date] {
        (0...6).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }
    static var defaultTime: Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today) ?? today
    }

    static func minutesSinceMidnight(_ date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func nearbySlots(_ slots: [ReservationSlot], desiredTime: Date) -> [ReservationSlot] {
        return Array(slots.sorted { lhs, rhs in
            let left = distanceFromDesired(lhs, desiredTime: desiredTime)
            let right = distanceFromDesired(rhs, desiredTime: desiredTime)
            return left == right ? lhs.startAt > rhs.startAt : left < right
        }.prefix(3)).sorted { $0.startAt < $1.startAt }
    }

    static func closestStart(_ slots: [ReservationSlot], desiredTime: Date) -> Date? {
        slots.min { lhs, rhs in
            let left = distanceFromDesired(lhs, desiredTime: desiredTime)
            let right = distanceFromDesired(rhs, desiredTime: desiredTime)
            return left == right ? lhs.startAt > rhs.startAt : left < right
        }?.startAt
    }

    private static func distanceFromDesired(_ slot: ReservationSlot, desiredTime: Date) -> Int {
        let roundedMinutes = ((minutesSinceMidnight(desiredTime) + 7) / 15) * 15
        return abs(minutesSinceMidnight(slot.startAt) - roundedMinutes)
    }

    static func text(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = london
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    static func price(_ pence: Int) -> String {
        (Double(pence) / 100).formatted(.currency(code: "GBP").locale(Locale(identifier: "en_GB")))
    }

    static func duration(_ option: ReservationDuration) -> String {
        let hours = option.minutes / 60
        let minutes = option.minutes % 60
        return minutes == 0 ? "\(hours) hour\(hours == 1 ? "" : "s")" : "\(hours)h \(minutes)m"
    }

    static func dayLabel(_ date: Date) -> String {
        let offset = calendar.dateComponents([.day], from: today, to: date).day ?? 0
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return text(date, format: "EEE d")
        }
    }
}

struct PodReservationView: View {
    @Environment(AuthService.self) private var authService
    @Environment(AppRouter.self) private var appRouter
    @State private var pods: [ReservablePod] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var bookings: [MyPodReservation] = []
    @State private var now = Date.now
    @State private var notificationRoute: NotificationBookingRoute?
    @AppStorage("pendingPodReservationId") private var pendingId = ""

    private var nextBookings: [MyPodReservation] {
        let future = bookings.filter {
            $0.startAt > now && ($0.status == "paid" || $0.status == "confirmed")
        }
        guard let nextStart = future.map(\.startAt).min() else { return [] }
        return future.filter { $0.startAt == nextStart }
            .sorted { $0.podLabel < $1.podLabel }
    }

    var body: some View {
        NavigationStack {
            List {
                if let nextBooking = nextBookings.first {
                    Section {
                        NavigationLink {
                            if nextBookings.count == 1 {
                                MyBookingDetailView(booking: nextBooking) {
                                    Task { await loadBookings() }
                                }
                            } else {
                                NextPodBookingsView(bookings: nextBookings) {
                                    Task { await loadBookings() }
                                }
                            }
                        } label: {
                            Label(nextBookings.count == 1 ? "View your next booking" : "View your latest bookings",
                                  systemImage: "ticket")
                        }
                    }
                }
                Section("Available pods") {
                    if isLoading {
                        ProgressView("Loading pods…")
                    } else if let error {
                        ContentUnavailableView("Couldn't load pods", systemImage: "wifi.exclamationmark", description: Text(error))
                        Button("Try again") { Task { await loadPods() } }
                    } else if pods.isEmpty {
                        ContentUnavailableView("No pods available", systemImage: "square.dashed")
                    } else {
                        ForEach(pods) { pod in
                            NavigationLink {
                                PodBookingView(pod: pod)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pod.name).font(.headline)
                                    Text(pod.address).font(.subheadline).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pods")
            .navigationDestination(item: $notificationRoute) { route in
                if let booking = bookings.first(where: { $0.id == route.id }) {
                    MyBookingDetailView(booking: booking) {
                        Task { await loadBookings() }
                    }
                } else {
                    ContentUnavailableView("Booking unavailable", systemImage: "calendar.badge.exclamationmark",
                                           description: Text("We couldn't find this booking. Please refresh or check My Bookings."))
                        .overlay(alignment: .bottom) {
                            Button("Try again") { Task { await loadBookings() } }
                                .padding(.bottom, 80)
                        }
                }
            }
            .task(id: authService.session?.user.id) { await loadPods() }
            .onAppear { Task { await loadBookings() } }
            .task(id: appRouter.pendingBookingId) {
                guard let id = appRouter.pendingBookingId else { return }
                await loadBookings()
                guard !Task.isCancelled else { return }
                notificationRoute = NotificationBookingRoute(id: id)
                appRouter.pendingBookingId = nil
            }
            .onChange(of: authService.session?.user.id) { _, _ in
                Task { await loadBookings() }
            }
            .onChange(of: pendingId) { _, _ in
                Task { await loadBookings() }
            }
            .task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(15)) }
                    catch { return }
                    now = .now
                }
            }
            .refreshable {
                await loadPods()
                await loadBookings()
            }
        }
    }

    private func loadPods() async {
        isLoading = true
        error = nil
        do { pods = try await ReservationAPIClient.shared.pods(accessToken: authService.session?.accessToken) }
        catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private func loadBookings() async {
        guard let session = authService.session else {
            bookings = []
            await ReservationReminderService.sync([])
            return
        }
        do {
            let latest = try await ReservationAPIClient.shared.myBookings(accessToken: session.accessToken)
            guard authService.session?.user.id == session.user.id else { return }
            now = .now
            bookings = latest
            await ReservationReminderService.sync(latest)
        } catch {
            reservationLog.error("Next booking load failed: \(error.localizedDescription, privacy: .private)")
            bookings = []
        }
    }
}

private struct NextPodBookingsView: View {
    @Environment(AuthService.self) private var authService
    @State private var bookings: [MyPodReservation]
    let startAt: Date
    let onUpdated: () -> Void

    init(bookings: [MyPodReservation], onUpdated: @escaping () -> Void) {
        _bookings = State(initialValue: bookings)
        startAt = bookings[0].startAt
        self.onUpdated = onUpdated
    }

    var body: some View {
        Group {
            if bookings.isEmpty {
                ContentUnavailableView("No bookings at this time", systemImage: "calendar")
            } else {
                List(bookings) { booking in
                    NavigationLink {
                        MyBookingDetailView(booking: booking) {
                            Task {
                                await refresh()
                                onUpdated()
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(booking.podLabel).font(.headline)
                            Text(PodTime.text(booking.startAt, format: "EEE d MMM yyyy, h:mm a"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
        .navigationTitle("Next bookings")
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        guard let session = authService.session else {
            bookings = []
            return
        }
        do {
            let latest = try await ReservationAPIClient.shared.myBookings(accessToken: session.accessToken)
            guard authService.session?.user.id == session.user.id else { return }
            bookings = latest.filter {
                $0.startAt == startAt && ($0.status == "paid" || $0.status == "confirmed")
            }.sorted { $0.podLabel < $1.podLabel }
        } catch {
            reservationLog.error("Next bookings list refresh failed: \(error.localizedDescription, privacy: .private)")
        }
    }
}

struct PodBookingView: View {
    let pod: ReservablePod
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var day = PodTime.today
    @State private var desiredTime = PodTime.defaultTime
    @State private var showTimePicker = false
    @State private var showDetails = false
    @State private var availability: ReservationAvailability?
    @State private var selectedStart: Date?
    @State private var selectedDuration: ReservationDuration?
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var error: String?
    @State private var hold: ReservationHold?
    @State private var paymentSheet: PaymentSheet?
    @State private var showPaymentSheet = false
    @State private var paymentPresentationID: UUID?
    @State private var paymentReservationId: String?
    @State private var statusReservationId: String?
    @State private var showStatus = false
    @AppStorage("pendingPodReservationId") private var pendingId = ""
    @AppStorage("pendingPodReservationAccountId") private var pendingAccountId = ""

    private var chosenSlot: ReservationSlot? {
        availability?.slots.first { $0.startAt == selectedStart }
    }

    private var nearbySlots: [ReservationSlot] {
        PodTime.nearbySlots(availability?.slots ?? [], desiredTime: desiredTime)
    }

    private var isValid: Bool {
        selectedStart != nil && selectedDuration != nil &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        authService.session?.user.email?.contains("@") == true &&
        (phone.isEmpty || (phone.hasPrefix("+") && phone.dropFirst().allSatisfy(\.isNumber)))
    }

    private var isDark: Bool { colorScheme == .dark }
    private var background: Color { isDark ? Color(white: 0.18) : Color.brandSecondary }
    private var card: Color { isDark ? Color(white: 0.12) : Color.brandSurface }
    private var primaryText: Color { isDark ? .white : Color.brandPrimary }
    private var muted: Color { isDark ? Color(white: 0.72) : Color.brandMutedText }
    private var border: Color { isDark ? .white.opacity(0.1) : Color.brandBorder }
    private var buttonBackground: Color { isDark ? .white : Color.brandPrimary }
    private var buttonText: Color { isDark ? .black : Color.brandSecondary }
    private func choiceFill(_ selected: Bool) -> Color {
        selected ? buttonBackground : card
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    podHeader
                    Rectangle().fill(border).frame(height: 1)
                        .padding(.top, 24).padding(.bottom, 26)
                    if showDetails {
                        detailsContent
                    } else {
                        selectionContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
            footer
        }
        .background(background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showTimePicker) { timePickerSheet }
        .task(id: PodTime.text(day, format: "yyyy-MM-dd")) { await loadAvailability() }
        .onAppear {
            name = authService.displayName ?? ""
            email = authService.session?.user.email ?? ""
        }
        .onChange(of: selectedStart) { _, _ in
            guard paymentPresentationID == nil && !showStatus else { return }
            selectedDuration = nil
            discardHold(reason: "start_changed")
        }
        .onChange(of: desiredTime) { _, time in selectClosestStart(to: time) }
        .onChange(of: selectedDuration) { _, _ in
            if paymentPresentationID == nil && !showStatus { discardHold(reason: "duration_changed") }
        }
        .onChange(of: name) { _, _ in
            if paymentPresentationID == nil && !showStatus { discardHold(reason: "name_changed") }
        }
        .onChange(of: phone) { _, _ in
            if paymentPresentationID == nil && !showStatus { discardHold(reason: "phone_changed") }
        }
        .modifier(BookingPaymentModifier(
            paymentSheet: paymentSheet,
            isPresented: $showPaymentSheet,
            onCompletion: handlePaymentResult
        ))
        .task(id: paymentPresentationID) {
            guard paymentPresentationID != nil, paymentSheet != nil else { return }
            // Present after SwiftUI has installed the PaymentSheet modifier.
            reservationLog.info("Checkout stage=present_sheet reservation=\(hold?.reservationId ?? "none", privacy: .public)")
            showPaymentSheet = true
        }
        .task(id: hold?.reservationId) {
            guard let hold else { return }
            let remaining = hold.holdExpiresAt.timeIntervalSinceNow
            if remaining > 0 {
                do { try await Task.sleep(for: .seconds(remaining)) }
                catch { return }
            }
            guard !showStatus && paymentPresentationID == nil else { return }
            reservationLog.warning("Reservation hold expired in app reservation=\(hold.reservationId, privacy: .public)")
            showPaymentSheet = false
            discardHold(reason: "expired")
            await loadAvailability()
            error = "The payment window expired. Please choose your time again."
        }
        .navigationDestination(isPresented: $showStatus) {
            if let statusReservationId {
                PodReservationStatusView(reservationId: statusReservationId)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                if showDetails { showDetails = false } else { dismiss() }
            } label: {
                Image(systemName: "arrow.left").font(.system(size: 20, weight: .medium))
                    .frame(width: 42, height: 42)
            }
            Spacer()
            Text(showDetails ? "Your details" : "Reserve a pod")
                .font(.dmSans(20, weight: .semibold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 20, weight: .medium))
                    .frame(width: 42, height: 42)
            }
        }
        .foregroundStyle(primaryText)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var podHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(pod.name)
                .font(.dmSans(23, weight: .semibold))
                .foregroundStyle(primaryText)
            Label(pod.address, systemImage: "mappin.circle")
                .font(.dmSans(13))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("When do you need it?")
                .font(.dmSans(24, weight: .bold))
                .foregroundStyle(primaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PodTime.bookableDays, id: \.self) { date in
                        let selected = PodTime.text(day, format: "yyyy-MM-dd") == PodTime.text(date, format: "yyyy-MM-dd")
                        Button { day = date } label: {
                            Text(PodTime.dayLabel(date))
                                .font(.dmSans(15, weight: .medium))
                                .foregroundStyle(selected ? buttonText : primaryText)
                                .frame(minWidth: 92)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 13)
                                .background(choiceFill(selected), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(selected ? .clear : border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.trailing, 1)

            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("What time would you like to start?")
                Button { showTimePicker = true } label: {
                    HStack {
                        Text("Desired time")
                            .foregroundStyle(primaryText)
                        Spacer()
                        Text(PodTime.text(desiredTime, format: "HH:mm"))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.brandPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.brandPrimary)
                    }
                    .font(.dmSans(15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                    .background(card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                if isLoading {
                    ProgressView("Checking availability…").tint(primaryText)
                        .foregroundStyle(muted)
                } else if let availability, availability.slots.isEmpty {
                    Text("No times available on this date.")
                        .foregroundStyle(muted)
                } else if let availability {
                    Text("Nearest available 15-minute starts")
                        .font(.dmSans(12))
                        .foregroundStyle(muted)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(nearbySlots) { slot in
                            choiceButton(PodTime.text(slot.startAt, format: "HH:mm"),
                                         selected: selectedStart == slot.startAt) {
                                selectedStart = slot.startAt
                            }
                        }
                    }
                }
            }

            if let slot = chosenSlot {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("Duration")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(slot.durations, id: \.minutes) { duration in
                                choiceButton(PodTime.duration(duration), selected: selectedDuration == duration) {
                                    selectedDuration = duration
                                }
                            }
                        }
                    }
                }
            }

            if selectedDuration != nil { summaryCard }
            if let error { errorText(error) }
        }
    }

    private var timePickerSheet: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Choose a start time")
                    .font(.dmSans(18, weight: .semibold))
                    .foregroundStyle(primaryText)
                Spacer()
                Button("Done") { showTimePicker = false }
                    .font(.dmSans(15, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
            }
            DatePicker("Desired time", selection: $desiredTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.wheel)
                .environment(\.timeZone, PodTime.london)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .background(background.ignoresSafeArea())
        .preferredColorScheme(colorScheme)
    }

    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Almost there")
                .font(.dmSans(24, weight: .bold))
                .foregroundStyle(primaryText)
            Text("We'll email your access code and directions after your booking is confirmed.")
                .font(.dmSans(14))
                .foregroundStyle(muted)
            detailField("Full name") {
                TextField("Full name", text: $name).textContentType(.name)
            }
            detailField("Email address") {
                Text(authService.session?.user.email ?? email)
                    .font(.dmSans(15))
                    .foregroundStyle(primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            detailField("Phone number (optional)") {
                TextField("+44…", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            }
            Text("Add an international-format phone number for WhatsApp reminders where available. Your email is required for the access code.")
                .font(.dmSans(12))
                .foregroundStyle(muted)
            if selectedDuration != nil { summaryCard }
            if let error { errorText(error) }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Reservation").foregroundStyle(muted)
                Spacer()
                if let selectedStart {
                    Text("\(PodTime.dayLabel(day)), \(PodTime.text(selectedStart, format: "HH:mm"))")
                }
            }
            HStack {
                Text("Duration").foregroundStyle(muted)
                Spacer()
                if let selectedDuration { Text("\(selectedDuration.minutes) minutes") }
            }
            HStack {
                Text("Total").fontWeight(.bold)
                Spacer()
                if let selectedDuration {
                    Text(PodTime.price(selectedDuration.amountPence)).fontWeight(.bold)
                }
            }
            .padding(.top, 7)
        }
        .font(.dmSans(15))
        .foregroundStyle(primaryText)
        .padding(18)
        .background(card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                if showDetails { Task { await reserve() } }
                else { showDetails = true }
            } label: {
                HStack(spacing: 10) {
                    if isCreating { ProgressView().tint(buttonText) }
                    else {
                        Text(showDetails ? "Continue to secure payment" : "Continue to payment")
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.dmSans(16, weight: .semibold))
                .foregroundStyle(buttonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(buttonBackground, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isCreating || (showDetails ? !isValid : selectedStart == nil || selectedDuration == nil))
            .opacity(isCreating || (showDetails ? !isValid : selectedStart == nil || selectedDuration == nil) ? 0.45 : 1)
            if showDetails {
                Text("You'll have 10 minutes to complete payment after continuing.")
                    .font(.dmSans(11))
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(background)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.dmSans(17, weight: .medium)).foregroundStyle(primaryText)
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dmSans(15, weight: .medium))
                .foregroundStyle(selected ? buttonText : primaryText.opacity(0.78))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 13)
                .padding(.vertical, 13)
                .background(choiceFill(selected), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? .clear : border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func detailField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)
            content()
                .font(.dmSans(15))
                .foregroundStyle(primaryText)
                .padding(15)
                .background(card, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(.dmSans(13))
            .foregroundStyle(isDark ? Color(red: 1, green: 0.65, blue: 0.65) : Color.red)
    }

    private func loadAvailability() async {
        guard paymentPresentationID == nil && !showStatus else {
            reservationLog.info("Availability reload deferred during checkout reservation=\(paymentReservationId ?? "none", privacy: .public)")
            return
        }
        isLoading = true
        error = nil
        selectedStart = nil
        selectedDuration = nil
        discardHold(reason: "availability_reloaded")
        do {
            guard let token = authService.session?.accessToken else {
                throw ReservationAPIError.server("Sign in to book a pod.")
            }
            let response = try await ReservationAPIClient.shared.availability(
                podId: pod.id, day: day, accessToken: token)
            availability = ReservationAvailability(
                date: response.date,
                slots: response.slots.filter {
                    Calendar(identifier: .gregorian).dateComponents(in: PodTime.london, from: $0.startAt).hour! >= 8
                }
            )
            selectClosestStart(to: desiredTime)
        } catch {
            availability = nil
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func discardHold(reason: String) {
        if let hold {
            reservationLog.info("Reservation hold cleared reservation=\(hold.reservationId, privacy: .public) reason=\(reason, privacy: .public)")
        }
        hold = nil
        paymentSheet = nil
        paymentPresentationID = nil
    }

    private func selectClosestStart(to time: Date) {
        selectedStart = PodTime.closestStart(availability?.slots ?? [], desiredTime: time)
    }

    private func handlePaymentResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            let persistedId = pendingAccountId == authService.session?.user.id.uuidString && !pendingId.isEmpty
                ? pendingId : nil
            let reservationId = paymentReservationId ?? hold?.reservationId ?? persistedId
            reservationLog.info("PaymentSheet completed reservation=\(reservationId ?? "none", privacy: .public)")
            if let reservationId {
                statusReservationId = reservationId
                showStatus = true
            } else {
                error = "Payment completed, but this screen lost the booking reference. Check My Bookings for confirmation."
            }
        case .failed(let paymentError):
            reservationLog.error("Checkout stage=sheet_failed reservation=\(paymentReservationId ?? hold?.reservationId ?? "none", privacy: .public) diagnostic=\(checkoutDiagnostic(paymentError), privacy: .public)")
            error = paymentError.localizedDescription
            paymentPresentationID = nil
        case .canceled:
            reservationLog.info("PaymentSheet dismissed reservation=\(paymentReservationId ?? hold?.reservationId ?? "none", privacy: .public)")
            paymentPresentationID = nil
        }
    }

    private func reserve() async {
        guard let selectedStart, let selectedDuration, isValid,
              let token = authService.session?.accessToken else { return }
        error = nil
        isCreating = true
        defer { isCreating = false }
        do {
            let currentHold: ReservationHold
            if let hold, hold.holdExpiresAt > .now {
                currentHold = hold
                reservationLog.info("Checkout stage=reuse_hold reservation=\(hold.reservationId, privacy: .public)")
            } else {
                reservationLog.info("Checkout stage=create_hold")
                currentHold = try await ReservationAPIClient.shared.create(
                    podId: pod.id, startAt: selectedStart, durationMinutes: selectedDuration.minutes,
                    name: name, email: authService.session?.user.email ?? email,
                    phone: phone.isEmpty ? nil : phone, accessToken: token
                )
                hold = currentHold
                pendingId = currentHold.reservationId
                pendingAccountId = authService.session?.user.id.uuidString ?? ""
                reservationLog.info("Reservation checkout created reservation=\(currentHold.reservationId, privacy: .public) expires=\(currentHold.holdExpiresAt.description, privacy: .public)")
            }
            guard currentHold.holdExpiresAt > .now else {
                discardHold(reason: "expired_before_checkout")
                error = "The payment window expired. Please choose your time again."
                return
            }
            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "Qwip"
            configuration.returnURL = "qwip://stripe-redirect"
            configuration.allowsDelayedPaymentMethods = false
            reservationLog.info("Checkout stage=prepare_sheet reservation=\(currentHold.reservationId, privacy: .public)")
            paymentReservationId = currentHold.reservationId
            paymentSheet = PaymentSheet(paymentIntentClientSecret: currentHold.clientSecret, configuration: configuration)
            paymentPresentationID = UUID()
        } catch ReservationAPIError.slotTaken {
            reservationLog.warning("Reservation slot taken before checkout")
            await loadAvailability()
            error = ReservationAPIError.slotTaken.localizedDescription
        } catch {
            reservationLog.error("Checkout stage=setup_failed diagnostic=\(checkoutDiagnostic(error), privacy: .public)")
            self.error = error.localizedDescription
        }
    }
}

struct BookingPaymentModifier: ViewModifier {
    let paymentSheet: PaymentSheet?
    @Binding var isPresented: Bool
    let onCompletion: (PaymentSheetResult) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if let paymentSheet {
            content.paymentSheet(isPresented: $isPresented, paymentSheet: paymentSheet, onCompletion: onCompletion)
        } else {
            content
        }
    }
}

struct PodReservationStatusView: View {
    let reservationId: String
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss
    @State private var status: ReservationStatus?
    @State private var message: String?
    @State private var checking = false
    @State private var confirmedBooking: MyPodReservation?
    @State private var calendarEvent: ReservationCalendarEvent?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if status?.isConfirmed == true {
                ReservationConfirmedView(
                    booking: confirmedBooking,
                    codeEmailed: status?.codeEmailed == true,
                    checking: checking,
                    onCalendar: {
                        guard let confirmedBooking else { return }
                        calendarEvent = ReservationCalendarEvent(booking: confirmedBooking)
                    },
                    onRefresh: { Task { await poll() } }
                )
            } else {
                waitingContent
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(status?.isConfirmed == true ? Color(hex: "1F3D32") : Color.brandPrimary)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(status?.isConfirmed == true ? 0.92 : 0.75), in: Circle())
            }
            .accessibilityLabel("Close booking status")
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.success, trigger: status?.isConfirmed == true)
        .task { await poll() }
        .sheet(item: $calendarEvent) { ReservationCalendarSheet(booking: $0) }
    }

    private var waitingContent: some View {
        VStack(spacing: 18) {
            if checking { ProgressView().tint(Color.brandPrimary) }
            Image(systemName: status?.isTerminalFailure == true ? "exclamationmark.circle" : "clock")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Color.brandPrimary)
            Text(title)
                .font(.dmSans(26, weight: .bold))
                .foregroundStyle(Color.brandPrimary)
            Text(message ?? detail)
                .font(.dmSans(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.brandMutedText)
            Button("Check again") { Task { await poll() } }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandPrimary)
                .disabled(checking)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandSecondary.ignoresSafeArea())
    }

    private var title: String {
        if status?.isConfirmed == true { return "You're booked" }
        if status?.isTerminalFailure == true { return "Booking not completed" }
        return "Checking your booking"
    }

    private var detail: String {
        if status?.isConfirmed == true {
            let emailDetail = status?.codeEmailed == true
                ? "Your access code and directions were sent by email."
                : "Your booking is confirmed. Your access code and directions will arrive by email."
            return emailDetail + " Allow notifications for reminders before your booking starts and ends."
        }
        if let status, status.isTerminalFailure { return "Reservation status: \(status.status). Please choose another time if needed." }
        return "Payment confirmation can take a moment. You can safely check again."
    }

    private func poll() async {
        checking = true
        message = nil
        defer { checking = false }
        for attempt in 0..<45 {
            do {
                status = try await ReservationAPIClient.shared.status(id: reservationId)
                reservationLog.info("Reservation status reservation=\(reservationId, privacy: .public) state=\(status?.status ?? "unknown", privacy: .public)")
                if status?.isConfirmed == true {
                    if let token = authService.session?.accessToken,
                       let bookings = try? await ReservationAPIClient.shared.myBookings(accessToken: token) {
                        confirmedBooking = bookings.first { $0.id == reservationId }
                        await ReservationReminderService.sync(bookings)
                    }
                    return
                }
                if status?.isTerminalFailure == true { return }
            } catch {
                message = error.localizedDescription
                return
            }
            if attempt < 44 {
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
            }
        }
        message = "Confirmation is taking longer than usual. Please check again shortly."
    }
}

private struct ReservationConfirmedView: View {
    let booking: MyPodReservation?
    let codeEmailed: Bool
    let checking: Bool
    let onCalendar: () -> Void
    let onRefresh: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backgroundExpanded = false
    @State private var badgeVisible = false
    @State private var checkDrawn = false
    @State private var contentVisible = false

    private let green = Color(hex: "1F3D32")

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.brandSecondary.ignoresSafeArea()
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "2C634C"), green, Color(hex: "122D23")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: max(geometry.size.width, geometry.size.height) * 2.5,
                           height: max(geometry.size.width, geometry.size.height) * 2.5)
                    .scaleEffect(backgroundExpanded ? 1 : 0.001)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 40)
                        confirmationBadge
                            .padding(.bottom, 30)
                        VStack(spacing: 13) {
                            Text("You're Booked!")
                                .font(.dmSans(38, weight: .bold))
                                .minimumScaleFactor(0.8)
                                .lineLimit(1)
                                .foregroundStyle(.white)
                            Text(codeEmailed
                                 ? "Your access code and directions are in your email."
                                 : "Your access code and directions are on their way.")
                                .font(.dmSans(15))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .opacity(contentVisible ? 1 : 0)
                        .offset(y: contentVisible ? 0 : 16)

                        if let booking {
                            bookingSummary(booking)
                                .padding(.top, 34)
                                .opacity(contentVisible ? 1 : 0)
                                .offset(y: contentVisible ? 0 : 16)
                        }
                        Spacer(minLength: 36)
                        actions
                            .opacity(contentVisible ? 1 : 0)
                            .offset(y: contentVisible ? 0 : 16)
                            .allowsHitTesting(contentVisible)
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 32)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task { await animateEntrance() }
    }

    private var confirmationBadge: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 1)
                .frame(width: 198, height: 198)
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.58))
                    .frame(width: 4, height: 13)
                    .offset(y: -115)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Circle()
                .fill(.white)
                .frame(width: 144, height: 144)
                .shadow(color: .black.opacity(0.16), radius: 20, y: 12)
            BookingCheckmark()
                .trim(from: 0, to: checkDrawn ? 1 : 0)
                .stroke(green, style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                .frame(width: 76, height: 76)
        }
        .frame(width: 230, height: 230)
        .scaleEffect(badgeVisible ? 1 : 0.45)
        .opacity(badgeVisible ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Booking confirmed")
    }

    private func bookingSummary(_ booking: MyPodReservation) -> some View {
        VStack(spacing: 8) {
            Text(booking.podLabel)
                .font(.dmSans(18, weight: .semibold))
            Text(PodTime.text(booking.startAt, format: "EEEE d MMMM · h:mm a") +
                 " – " + PodTime.text(booking.endAt, format: "h:mm a"))
                .font(.dmSans(14))
                .foregroundStyle(.white.opacity(0.78))
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.18)))
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if let booking {
                Button(action: onCalendar) {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                        .font(.dmSans(16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(green)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))

                NavigationLink {
                    MyBookingDetailView(booking: booking, onRescheduled: onRefresh)
                } label: {
                    Text("View booking details")
                        .font(.dmSans(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            } else {
                if checking { ProgressView().tint(.white) }
                Button("Load booking details", action: onRefresh)
                    .font(.dmSans(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .disabled(checking)
            }
        }
    }

    private func animateEntrance() async {
        if reduceMotion {
            backgroundExpanded = true
            badgeVisible = true
            checkDrawn = true
            contentVisible = true
            return
        }
        withAnimation(.easeOut(duration: 0.72)) { backgroundExpanded = true }
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) { badgeVisible = true }
        do { try await Task.sleep(for: .milliseconds(240)) } catch { return }
        withAnimation(.easeInOut(duration: 0.42)) { checkDrawn = true }
        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        withAnimation(.easeOut(duration: 0.45)) { contentVisible = true }
    }
}

private struct BookingCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width * 0.4, y: rect.height * 0.73))
        path.addLine(to: CGPoint(x: rect.width * 0.86, y: rect.height * 0.25))
        return path
    }
}

#Preview("Booking confirmed") {
    ReservationConfirmedView(booking: nil, codeEmailed: true, checking: false,
                             onCalendar: {}, onRefresh: {})
}
