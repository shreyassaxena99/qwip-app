import SwiftUI

struct SavedSpotsView: View {
    @Environment(SavedSpotService.self) var savedSpotService
    @State private var detailSpot: SpotDetail? = nil
    @State private var isFetchingDetail = false
    @State private var fetchDetailError: String? = nil
    @State private var unsaveError: String? = nil

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if savedSpotService.isLoading && savedSpotService.savedEntries.isEmpty {
                    VStack {
                        Spacer(minLength: 120)
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(Color.brandPrimary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if let error = savedSpotService.loadError {
                    VStack(spacing: 16) {
                        Spacer(minLength: 120)
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(Color.brandPrimary.opacity(0.4))
                        Text(error)
                            .font(.dmSans(14))
                            .foregroundStyle(Color.brandPrimary.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Try Again") {
                            Task { await savedSpotService.load() }
                        }
                        .font(.dmSans(14, weight: .bold))
                        .foregroundStyle(Color.brandPrimary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if savedSpotService.savedEntries.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(savedSpotService.savedEntries) { entry in
                            SavedSpotCard(spot: entry.spot, isLoading: isFetchingDetail)
                                .onTapGesture { fetchDetail(for: entry.spot) }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task {
                                            do {
                                                try await savedSpotService.unsave(spotId: entry.spot.id)
                                            } catch {
                                                unsaveError = error.localizedDescription
                                            }
                                        }
                                    } label: {
                                        Label("Remove", systemImage: "heart.slash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .refreshable { await savedSpotService.load() }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.large)
            .background(Color.brandSecondary.ignoresSafeArea())
            .sheet(item: $detailSpot) { detail in
                SpotDetailView(detail: detail)
            }
            .alert("Error", isPresented: Binding(
                get: { fetchDetailError != nil },
                set: { if !$0 { fetchDetailError = nil } }
            )) {
                Button("OK") { fetchDetailError = nil }
            } message: {
                Text(fetchDetailError ?? "")
            }
            .alert("Couldn't remove spot", isPresented: Binding(
                get: { unsaveError != nil },
                set: { if !$0 { unsaveError = nil } }
            )) {
                Button("OK") { unsaveError = nil }
            } message: {
                Text(unsaveError ?? "")
            }
        }
    }

    private func fetchDetail(for pin: SpotPin) {
        guard !isFetchingDetail else { return }
        Task {
            isFetchingDetail = true
            do {
                detailSpot = try await SpotAPIClient.shared.fetchSpotDetail(id: pin.id)
            } catch SpotAPIError.notFound {
                fetchDetailError = "This spot is no longer available."
            } catch {
                fetchDetailError = error.localizedDescription
            }
            isFetchingDetail = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.brandPrimary.opacity(0.06), lineWidth: 20)
                    .frame(width: 140)
                Circle()
                    .stroke(Color.brandPrimary.opacity(0.1), lineWidth: 1.5)
                    .frame(width: 100)
                ZStack {
                    Circle()
                        .fill(Color.brandPrimary.opacity(0.08))
                        .frame(width: 80)
                    Image(systemName: "heart")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.brandPrimary.opacity(0.5))
                }
            }
            VStack(spacing: 6) {
                Text("Nothing saved yet")
                    .font(.dmSans(22, weight: .heavy))
                    .foregroundStyle(Color.brandPrimary)
                Text("Find spots on the map and\ntap ♥ to save them here.")
                    .font(.dmSans(15))
                    .foregroundStyle(Color.brandPrimary.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Saved Spot Card (grid cell)

private struct SavedSpotCard: View {
    let spot: SpotPin
    let isLoading: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color.brandPrimary.opacity(0.06))
                .frame(width: 70)
                .offset(x: 16, y: -16)
                .blur(radius: 8)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.brandPrimary)
                            .frame(width: 36, height: 36)
                        Image(systemName: spot.category.systemIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.brandSecondary)
                    }
                    .shadow(color: Color.brandPrimary.opacity(0.35), radius: 6, x: 0, y: 2)
                    Spacer()
                    OpenBadge(isOpen: spot.isOpenNow)
                }

                Text(spot.name)
                    .font(.dmSans(14, weight: .heavy))
                    .foregroundStyle(Color.brandPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(spot.category.displayName.uppercased())
                    .font(.dmSans(8.5, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(Color.brandPrimary.opacity(0.4))

                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text(spot.formattedRating)
                        .font(.dmSans(13, weight: .black))
                        .foregroundStyle(Color.brandPrimary)
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
            .padding(14)
        }
        .background(glassBackground(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.brandPrimary.opacity(0.1), radius: 14, x: 0, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}
