import SwiftUI
import Supabase
import PostHog

// MARK: - Profile Field (used by About You sub-view)

private enum ProfileField: Identifiable {
    case workingStyle, homeArea, workArea
    var id: Self { self }

    var question: String {
        switch self {
        case .workingStyle: return "How do you work?"
        case .homeArea:     return "Where do you live in London?"
        case .workArea:     return "Where do you work in London?"
        }
    }

    var options: [String] {
        switch self {
        case .workingStyle:
            return ["Fully remote", "Office-based", "Freelance / self-employed", "Student", "Other"]
        case .homeArea, .workArea:
            return ["North London", "West London", "North West London", "East London",
                    "South East London", "South West London", "Central London", "Outside London"]
        }
    }

    var iconName: String {
        switch self {
        case .workingStyle: return "ic_briefcase"
        case .homeArea:     return "ic_house"
        case .workArea:     return "ic_building_2"
        }
    }

    var iconColor: Color {
        switch self {
        case .workingStyle: return Color(hex: "5E6AD2")
        case .homeArea:     return Color(hex: "34C759")
        case .workArea:     return Color(hex: "1f3d32")
        }
    }
}

// MARK: - Navigation destinations

private enum ProfileDestination: Hashable {
    case aboutYou, preferences, about, myAccount
}

// MARK: - ProfileView

struct ProfileView: View {
    @Environment(SpotStore.self) var store
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(AuthService.self) var authService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // Stats
                    HStack(spacing: 12) {
                        BigStatCard(
                            value: "\(savedSpotService.savedEntries.count)",
                            label: "Saved Spots",
                            icon: "ic_heart",
                            iconColor: Color(hex: "e74c3c")
                        )
                        BigStatCard(
                            value: "\(store.spots.count)",
                            label: "Spots Nearby",
                            icon: "ic_map_pin",
                            iconColor: Color.brandPrimary
                        )
                    }

                    // Menu
                    GlassCard {
                        menuRow("Personal Details", icon: "ic_user",       color: Color(hex: "1f3d32"), dest: .aboutYou)
                        Divider().overlay(Color.brandBorder).padding(.leading, 44)
                        menuRow("Preferences",     icon: "ic_settings",  color: Color(hex: "5E6AD2"), dest: .preferences)
                        Divider().overlay(Color.brandBorder).padding(.leading, 44)
                        menuRow("About",            icon: "ic_info",      color: Color(hex: "34C759"), dest: .about)
                        Divider().overlay(Color.brandBorder).padding(.leading, 44)
                        menuRow("Manage Account",  icon: "ic_circle_user", color: Color(hex: "FF9500"), dest: .myAccount)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.brandSecondary.ignoresSafeArea())
            .navigationTitle(authService.displayName.map { "Hello, \($0)" } ?? "Hello")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: ProfileDestination.self) { dest in
                switch dest {
                case .aboutYou:    AboutYouView()
                case .preferences: PreferencesView()
                case .about:       AboutAppView()
                case .myAccount:   MyAccountView()
                }
            }
        }
    }

    private func menuRow(_ title: String, icon: String, color: Color, dest: ProfileDestination) -> some View {
        NavigationLink(value: dest) {
            HStack(spacing: 12) {
                GlassIcon(iconName: icon, color: color)
                Text(title)
                    .font(.dmSans(14, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                Spacer()
                Image("ic_chevron_right")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(Color.brandPrimary.opacity(0.25))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - About You

private struct AboutYouView: View {
    @Environment(AuthService.self) var authService
    @State private var showingNameEdit = false
    @State private var editingName = ""
    @State private var workingStyle: String? = nil
    @State private var homeArea: String? = nil
    @State private var workArea: String? = nil
    @State private var isLoadingProfile = true
    @State private var editingField: ProfileField? = nil
    @State private var saveError: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    Button {
                        editingName = authService.displayName ?? ""
                        showingNameEdit = true
                    } label: {
                        HStack {
                            Label {
                                Text("Your name")
                                    .font(.dmSans(14, weight: .bold))
                                    .foregroundStyle(Color.brandPrimary)
                            } icon: {
                                GlassIcon(iconName: "ic_user", color: Color(hex: "5E6AD2"))
                            }
                            Spacer()
                            Text(authService.displayName ?? "–")
                                .font(.dmSans(13))
                                .foregroundStyle(Color.brandPrimary.opacity(authService.displayName != nil ? 0.5 : 0.3))
                            Image("ic_chevron_right")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 11, height: 11)
                                .foregroundStyle(Color.brandPrimary.opacity(0.25))
                        }
                    }
                    .buttonStyle(.plain)

                    Divider().overlay(Color.brandBorder).padding(.leading, 44)
                    profileFieldRow(.workingStyle)
                    Divider().overlay(Color.brandBorder).padding(.leading, 44)
                    profileFieldRow(.homeArea)
                    Divider().overlay(Color.brandBorder).padding(.leading, 44)
                    profileFieldRow(.workArea)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.brandSecondary.ignoresSafeArea())
        .navigationTitle("Personal Details")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadProfile() }
        .alert("Edit Name", isPresented: $showingNameEdit) {
            TextField("Display name", text: $editingName)
            Button("Save") {
                let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    Task { try? await authService.updateProfile(displayName: trimmed) }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(item: $editingField) { field in
            let current: String? = {
                switch field {
                case .workingStyle: return workingStyle
                case .homeArea:     return homeArea
                case .workArea:     return workArea
                }
            }()
            ProfileFieldPickerSheet(field: field, currentValue: current) { newValue in
                save(field: field, newValue: newValue)
            }
        }
        .alert("Couldn't Save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func profileFieldRow(_ field: ProfileField) -> some View {
        Button { editingField = field } label: {
            HStack {
                Label {
                    Text(field.question)
                        .font(.dmSans(14, weight: .bold))
                        .foregroundStyle(Color.brandPrimary)
                } icon: {
                    GlassIcon(iconName: field.iconName, color: field.iconColor)
                }
                Spacer()
                if isLoadingProfile {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.brandBorder)
                        .frame(width: 60, height: 12)
                } else {
                    let value: String? = {
                        switch field {
                        case .workingStyle: return workingStyle
                        case .homeArea:     return homeArea
                        case .workArea:     return workArea
                        }
                    }()
                    Text(value ?? "–")
                        .font(.dmSans(13))
                        .foregroundStyle(Color.brandPrimary.opacity(value != nil ? 0.5 : 0.3))
                }
                Image("ic_chevron_right")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(Color.brandPrimary.opacity(0.25))
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoadingProfile)
    }

    private func loadProfile() async {
        guard let session = authService.session else {
            isLoadingProfile = false
            return
        }
        if let profile = try? await UserProfileAPIClient.fetchProfile(
            userId: session.user.id.uuidString,
            token: session.accessToken
        ) {
            workingStyle = profile.workingStyle
            homeArea     = profile.homeArea
            workArea     = profile.workArea
        }
        isLoadingProfile = false
    }

    private func save(field: ProfileField, newValue: String) {
        let oldValue: String? = {
            switch field {
            case .workingStyle: return workingStyle
            case .homeArea:     return homeArea
            case .workArea:     return workArea
            }
        }()
        switch field {
        case .workingStyle: workingStyle = newValue
        case .homeArea:     homeArea = newValue
        case .workArea:     workArea = newValue
        }
        editingField = nil
        Task {
            do {
                guard let session = authService.session else { return }
                try await UserProfileAPIClient.saveProfile(
                    userId: session.user.id.uuidString,
                    token: session.accessToken,
                    workingStyle: field == .workingStyle ? newValue : nil,
                    homeArea:     field == .homeArea     ? newValue : nil,
                    workArea:     field == .workArea     ? newValue : nil
                )
            } catch {
                switch field {
                case .workingStyle: workingStyle = oldValue
                case .homeArea:     homeArea = oldValue
                case .workArea:     workArea = oldValue
                }
                saveError = error.localizedDescription
            }
        }
    }
}

// MARK: - Preferences

private struct PreferencesView: View {
    @Environment(AuthService.self) var authService
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("mapStyle") private var mapStyle = "standard"
    @AppStorage(AnalyticsConsentKey.decided) private var analyticsConsentDecided = false
    @AppStorage(AnalyticsConsentKey.accepted) private var analyticsConsentAccepted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    Toggle(isOn: Binding(
                        get: { authService.emailOptIn },
                        set: { newValue in
                            authService.emailOptIn = newValue
                            Task { try? await authService.updateProfile(emailOptIn: newValue) }
                        }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Email Updates")
                                    .font(.dmSans(14, weight: .bold))
                                    .foregroundStyle(Color.brandPrimary)
                                Text("New spots and local tips")
                                    .font(.dmSans(12))
                                    .foregroundStyle(Color.brandPrimary.opacity(0.5))
                            }
                        } icon: {
                            GlassIcon(iconName: "ic_mail", color: Color(hex: "1f3d32"))
                        }
                    }
                    .tint(Color.brandPrimary)

                    Divider().overlay(Color.brandBorder).padding(.leading, 44)

                    Toggle(isOn: Binding(
                        get: { analyticsConsentAccepted },
                        set: { newValue in
                            analyticsConsentAccepted = newValue
                            analyticsConsentDecided = true
                            if newValue {
                                PostHogSDK.shared.optIn()
                            } else {
                                PostHogSDK.shared.optOut()
                            }
                        }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Analytics")
                                    .font(.dmSans(14, weight: .bold))
                                    .foregroundStyle(Color.brandPrimary)
                                Text("Anonymous usage data")
                                    .font(.dmSans(12))
                                    .foregroundStyle(Color.brandPrimary.opacity(0.5))
                            }
                        } icon: {
                            GlassIcon(iconName: "ic_shield_check", color: Color(hex: "34C759"))
                        }
                    }
                    .tint(Color.brandPrimary)
                }

                GlassCard(header: "App Theme") {
                    Label {
                        Picker("App Theme", selection: $appTheme) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.segmented)
                    } icon: {
                        GlassIcon(iconName: "ic_sun_moon", color: Color(hex: "5E6AD2"))
                    }
                }

                GlassCard(header: "Map Style") {
                    Label {
                        Picker("Map Style", selection: $mapStyle) {
                            Text("Standard").tag("standard")
                            Text("Hybrid").tag("hybrid")
                        }
                        .pickerStyle(.segmented)
                    } icon: {
                        GlassIcon(iconName: "ic_map", color: Color(hex: "1f3d32"))
                    }
                }

                GlassCard {
                    Link(destination: URL(string: "https://qwip.co.uk/spots/suggest")!) {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Suggest a Spot")
                                        .font(.dmSans(14, weight: .bold))
                                        .foregroundStyle(Color.brandPrimary)
                                    Text("Know somewhere great? Let us know")
                                        .font(.dmSans(12))
                                        .foregroundStyle(Color.brandPrimary.opacity(0.5))
                                }
                            } icon: {
                                GlassIcon(iconName: "ic_map_pin", color: Color(hex: "34C759"))
                            }
                            Spacer()
                            Image("ic_arrow_up_right")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 11, height: 11)
                                .foregroundStyle(Color.brandPrimary.opacity(0.25))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.brandSecondary.ignoresSafeArea())
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - About

private struct AboutAppView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    LabeledContent {
                        Text("1.0.0")
                            .font(.dmSans(13, weight: .bold))
                            .foregroundStyle(Color.brandPrimary.opacity(0.5))
                    } label: {
                        Label {
                            Text("Version")
                                .font(.dmSans(14, weight: .bold))
                                .foregroundStyle(Color.brandPrimary)
                        } icon: {
                            GlassIcon(iconName: "ic_info", color: Color(hex: "5E6AD2"))
                        }
                    }

                    Divider().overlay(Color.brandBorder).padding(.leading, 44)

                    Link(destination: URL(string: "https://qwip.co.uk/privacy-policy")!) {
                        HStack {
                            Label {
                                Text("Privacy Policy")
                                    .font(.dmSans(14, weight: .bold))
                                    .foregroundStyle(Color.brandPrimary)
                            } icon: {
                                GlassIcon(iconName: "ic_shield_check", color: Color(hex: "34C759"))
                            }
                            Spacer()
                            Image("ic_arrow_up_right")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 11, height: 11)
                                .foregroundStyle(Color.brandPrimary.opacity(0.25))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.brandSecondary.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - My Account

private struct MyAccountView: View {
    @Environment(AuthService.self) var authService
    @Environment(\.signOut) var signOut
    @State private var showingReasonSheet = false
    @State private var selectedDeletionReason: String? = nil
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    Button { signOut() } label: {
                        HStack {
                            Label {
                                Text("Sign Out")
                                    .font(.dmSans(14, weight: .bold))
                                    .foregroundStyle(Color.brandPrimary)
                            } icon: {
                                GlassIcon(iconName: "ic_log_out", color: Color(hex: "FF9500"))
                            }
                            Spacer()
                            Image("ic_chevron_right")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 11, height: 11)
                                .foregroundStyle(Color.brandPrimary.opacity(0.25))
                        }
                    }
                    .buttonStyle(.plain)

                    Divider().overlay(Color.brandBorder).padding(.leading, 44)

                    Button(role: .destructive) {
                        showingReasonSheet = true
                    } label: {
                        HStack {
                            Label {
                                Text("Delete Account")
                                    .font(.dmSans(14, weight: .bold))
                            } icon: {
                                GlassIcon(iconName: "ic_trash_2", color: Color(hex: "FF3B30"))
                            }
                            Spacer()
                            if isDeleting {
                                ProgressView().scaleEffect(0.8).tint(Color.brandPrimary.opacity(0.4))
                            } else {
                                Image("ic_chevron_right")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 11, height: 11)
                                    .foregroundStyle(Color.brandPrimary.opacity(0.25))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.brandSecondary.ignoresSafeArea())
        .navigationTitle("Manage Account")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingReasonSheet, onDismiss: {
            // Reset so onChange re-fires if the user cancels and tries again with the same reason.
            // Skip reset if the confirmation dialog is already queued (reason was successfully selected).
            if !showingDeleteConfirmation {
                selectedDeletionReason = nil
            }
        }) {
            DeleteAccountReasonSheet { reason in
                selectedDeletionReason = reason
            }
        }
        .onChange(of: selectedDeletionReason) { _, reason in
            guard reason != nil else { return }
            showingDeleteConfirmation = true
        }
        .confirmationDialog("Delete Account?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                isDeleting = true
                Task {
                    do {
                        try await authService.deleteAccount(reason: selectedDeletionReason ?? "")
                    } catch {
                        deleteError = error.localizedDescription
                    }
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete your account and all saved spots. This action cannot be undone.")
        }
        .alert("Couldn't Delete Account", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }
}

// MARK: - Delete Account Reason Sheet

private struct DeleteAccountReasonSheet: View {
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: String? = nil

    private let reasons = [
        "I don't use qwip anymore",
        "Found a better alternative",
        "Moving out of London",
        "Technical issues",
        "Other"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Help us improve")
                        .font(.dmSans(14))
                        .foregroundStyle(Color.brandPrimary.opacity(0.5))
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    VStack(spacing: 0) {
                        ForEach(Array(reasons.enumerated()), id: \.offset) { index, reason in
                            if index > 0 {
                                Divider().overlay(Color.brandBorder)
                            }
                            reasonRow(reason)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(glassBackground(cornerRadius: 20))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.brandPrimary.opacity(0.08), radius: 24, x: 0, y: 8)
                    .padding(.horizontal, 24)

                    Button {
                        guard let reason = selectedReason else { return }
                        onSelect(reason)
                        dismiss()
                    } label: {
                        Text("Continue")
                            .font(.dmSans(14, weight: .black))
                            .tracking(0.3)
                            .foregroundStyle(Color.brandSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.brandPrimary.opacity(selectedReason != nil ? 1 : 0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedReason == nil)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }
                .padding(.bottom, 40)
            }
            .background(Color.brandSecondary.ignoresSafeArea())
            .navigationTitle("Why are you leaving?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Cancel")
                                .font(.dmSans(15))
                        }
                        .foregroundStyle(Color.brandPrimary)
                    }
                }
            }
        }
    }

    private func reasonRow(_ reason: String) -> some View {
        let selected = selectedReason == reason
        return Button {
            selectedReason = reason
        } label: {
            HStack {
                Text(reason)
                    .font(.dmSans(14, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                Spacer()
                ZStack {
                    Circle()
                        .stroke(selected ? Color.clear : Color.brandBorder, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle()
                            .fill(Color.brandPrimary)
                            .frame(width: 22, height: 22)
                        Image("ic_check")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(Color.brandSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(selected ? Color.brandPrimary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Card

private struct GlassCard<Content: View>: View {
    var header: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header.uppercased())
                    .font(.dmSans(9.5, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(Color.brandPrimary.opacity(0.4))
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .background(glassBackground(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.brandPrimary.opacity(0.08), radius: 14, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
        }
    }
}

// MARK: - Big Stat Card

private struct BigStatCard: View {
    let value: String
    let label: String
    let icon: String
    let iconColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(iconColor)
            Text(value)
                .font(.dmSans(36, weight: .black))
                .foregroundStyle(Color.brandPrimary)
            Text(label.uppercased())
                .font(.dmSans(9, weight: .black))
                .tracking(0.7)
                .foregroundStyle(Color.brandPrimary.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(glassBackground(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.brandPrimary.opacity(0.08), radius: 14, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
    }
}

// MARK: - Glass Icon

private struct GlassIcon: View {
    let iconName: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .frame(width: 28, height: 28)
            Image(iconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Profile Field Picker Sheet

private struct ProfileFieldPickerSheet: View {
    let field: ProfileField
    let currentValue: String?
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(field.options.enumerated()), id: \.offset) { index, option in
                            if index > 0 {
                                Divider().overlay(Color.brandBorder)
                            }
                            optionRow(option)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(glassBackground(cornerRadius: 20))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.brandPrimary.opacity(0.08), radius: 24, x: 0, y: 8)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }
                .padding(.bottom, 40)
            }
            .background(Color.brandSecondary.ignoresSafeArea())
            .navigationTitle(field.question)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Back")
                                .font(.dmSans(15))
                        }
                        .foregroundStyle(Color.brandPrimary)
                    }
                }
            }
        }
    }

    private func optionRow(_ option: String) -> some View {
        let selected = currentValue == option
        return Button {
            guard !selected else { return }
            onSave(option)
        } label: {
            HStack {
                Text(option)
                    .font(.dmSans(14, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                Spacer()
                ZStack {
                    Circle()
                        .stroke(selected ? Color.clear : Color.brandBorder, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle()
                            .fill(Color.brandPrimary)
                            .frame(width: 22, height: 22)
                        Image("ic_check")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(Color.brandSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(selected ? Color.brandPrimary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
