import SwiftUI

struct ProfileView: View {
    @Environment(SpotStore.self) var store
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(AuthService.self) var authService
    @Environment(\.signOut) var signOut
    @State private var showingDeleteConfirmation = false
    @State private var showingNameEdit = false
    @State private var editingName = ""

    var body: some View {
        @Bindable var bindableStore = store
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // MARK: Profile header
                    profileHeader

                    // MARK: Stats
                    HStack(spacing: 12) {
                        BigStatCard(value: "\(savedSpotService.savedEntries.count)", label: "Saved Spots", icon: "heart.fill", iconColor: Color(hex: "e74c3c"))
                        BigStatCard(value: "\(store.spots.count)", label: "Spots Nearby", icon: "mappin.circle.fill", iconColor: Color.brandPrimary)
                    }

                    // MARK: Preferences
                    GlassCard(header: "Preferences") {
                        Toggle(isOn: $bindableStore.emailOptIn) {
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
                                GlassIcon(systemName: "envelope.fill", color: .brandPrimary)
                            }
                        }
                        .tint(Color.brandPrimary)
                    }

                    // MARK: About
                    GlassCard(header: "About") {
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
                                GlassIcon(systemName: "info.circle.fill", color: Color(hex: "5E6AD2"))
                            }
                        }

                        Divider().overlay(Color.brandPrimary.opacity(0.08))
                            .padding(.leading, 44)

                        Link(destination: URL(string: "https://qwip.app/privacy")!) {
                            HStack {
                                Label {
                                    Text("Privacy Policy")
                                        .font(.dmSans(14, weight: .bold))
                                        .foregroundStyle(Color.brandPrimary)
                                } icon: {
                                    GlassIcon(systemName: "lock.shield.fill", color: Color(hex: "34C759"))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.brandPrimary.opacity(0.25))
                            }
                        }
                    }

                    // MARK: Account
                    GlassCard(header: "Account") {
                        Button {
                            signOut()
                        } label: {
                            HStack {
                                Label {
                                    Text("Sign Out")
                                        .font(.dmSans(14, weight: .bold))
                                        .foregroundStyle(Color.brandPrimary)
                                } icon: {
                                    GlassIcon(systemName: "rectangle.portrait.and.arrow.right", color: Color(hex: "FF9500"))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.brandPrimary.opacity(0.25))
                            }
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(Color.brandPrimary.opacity(0.08))
                            .padding(.leading, 44)

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Label {
                                    Text("Delete Account")
                                        .font(.dmSans(14, weight: .bold))
                                } icon: {
                                    GlassIcon(systemName: "trash.fill", color: Color(hex: "FF3B30"))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.brandPrimary.opacity(0.25))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.brandSecondary.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog("Delete Account?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) { }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete your account and all saved spots. This action cannot be undone.")
            }
            .alert("Edit Name", isPresented: $showingNameEdit) {
                TextField("Display name", text: $editingName)
                Button("Save") {
                    let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        Task { try? await authService.updateDisplayName(trimmed) }
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private var profileHeader: some View {
        ZStack(alignment: .topTrailing) {
            // Decorative orb
            Circle()
                .fill(Color.brandPrimary.opacity(0.07))
                .frame(width: 120)
                .offset(x: 20, y: -30)
                .blur(radius: 20)

            HStack(spacing: 16) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.brandPrimary)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.brandPrimary.opacity(0.4), radius: 10, x: 0, y: 4)
                    Text((authService.displayName ?? "?").prefix(1).uppercased())
                        .font(.dmSans(26, weight: .heavy))
                        .foregroundStyle(Color.brandSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(authService.displayName ?? "")
                        .font(.dmSans(18, weight: .heavy))
                        .foregroundStyle(Color.brandPrimary)
                    Text("QWIP MEMBER")
                        .font(.dmSans(9, weight: .black))
                        .tracking(1)
                        .foregroundStyle(Color.brandPrimary.opacity(0.4))
                }

                Spacer()

                Button {
                    editingName = authService.displayName ?? ""
                    showingNameEdit = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().stroke(Color.brandPrimary.opacity(0.15), lineWidth: 1))
                            .frame(width: 36, height: 36)
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(18)
        }
        .background(glassBackground(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.brandPrimary.opacity(0.1), radius: 16, x: 0, y: 5)
    }
}

// MARK: - Glass Card container

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
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
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
    let systemName: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .frame(width: 28, height: 28)
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
