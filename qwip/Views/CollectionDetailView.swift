import SwiftUI

// MARK: - Collection source

enum CollectionSource {
    case favourites
    case collection(Collection)

    var title: String {
        switch self {
        case .favourites: return "Favourite Spots"
        case .collection(let c): return c.name
        }
    }
}

// MARK: - View

struct CollectionDetailView: View {
    let source: CollectionSource
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(CollectionService.self) var collectionService

    // Used only for .collection case; .favourites reads from savedSpotService directly
    @State private var collectionEntries: [SavedSpotEntry] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var detailSpot: SpotDetail? = nil
    @State private var fetchingDetailID: String? = nil
    @State private var fetchDetailError: String? = nil
    @State private var removeError: String? = nil

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    // Reactive for .favourites; local state for .collection
    private var displayEntries: [SavedSpotEntry] {
        switch source {
        case .favourites:
            return savedSpotService.savedEntries.filter { $0.collectionIds.isEmpty }
        case .collection:
            return collectionEntries
        }
    }

    var body: some View {
        ScrollView {
            if isLoading && displayEntries.isEmpty {
                VStack {
                    Spacer(minLength: 120)
                    ProgressView().scaleEffect(1.2).tint(Color.brandPrimary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let error = loadError {
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
                    Button("Try Again") { Task { await loadEntries() } }
                        .font(.dmSans(14, weight: .bold))
                        .foregroundStyle(Color.brandPrimary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if displayEntries.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(displayEntries) { entry in
                        SavedSpotCard(spot: entry.spot, isLoading: fetchingDetailID == entry.spot.id)
                            .onTapGesture { fetchDetail(for: entry.spot) }
                            .contextMenu {
                                switch source {
                                case .favourites:
                                    Button(role: .destructive) {
                                        Task {
                                            do {
                                                try await savedSpotService.unsave(spotId: entry.spot.id)
                                            } catch {
                                                removeError = error.localizedDescription
                                            }
                                        }
                                    } label: {
                                        Label("Remove", systemImage: "heart.slash")
                                    }
                                case .collection(let c):
                                    Button(role: .destructive) {
                                        Task {
                                            do {
                                                try await collectionService.removeSpot(
                                                    spotId: entry.spot.id, fromCollection: c.id)
                                                collectionEntries.removeAll { $0.id == entry.id }
                                            } catch {
                                                removeError = error.localizedDescription
                                            }
                                        }
                                    } label: {
                                        Label("Remove from collection", systemImage: "folder.badge.minus")
                                    }
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .refreshable { await loadEntries() }
        .navigationTitle(source.title)
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
            get: { removeError != nil },
            set: { if !$0 { removeError = nil } }
        )) {
            Button("OK") { removeError = nil }
        } message: {
            Text(removeError ?? "")
        }
        .task { await loadEntries() }
    }

    // MARK: - Data

    private func loadEntries() async {
        guard case .collection(let c) = source else { return } // .favourites is always reactive
        isLoading = true
        loadError = nil
        do {
            collectionEntries = try await SavedSpotAPIClient.shared.fetchSavedSpots(collectionId: c.id)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func fetchDetail(for pin: SpotPin) {
        guard fetchingDetailID == nil else { return }
        Task {
            fetchingDetailID = pin.id
            do {
                detailSpot = try await SpotAPIClient.shared.fetchSpotDetail(id: pin.id)
            } catch SpotAPIError.notFound {
                fetchDetailError = "This spot is no longer available."
            } catch {
                fetchDetailError = error.localizedDescription
            }
            fetchingDetailID = nil
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().stroke(Color.brandPrimary.opacity(0.06), lineWidth: 20).frame(width: 140)
                Circle().stroke(Color.brandPrimary.opacity(0.1), lineWidth: 1.5).frame(width: 100)
                ZStack {
                    Circle().fill(Color.brandPrimary.opacity(0.08)).frame(width: 80)
                    Image(systemName: source == .favourites ? "heart" : "folder")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.brandPrimary.opacity(0.5))
                }
            }
            VStack(spacing: 6) {
                Text("No spots here yet")
                    .font(.dmSans(22, weight: .heavy))
                    .foregroundStyle(Color.brandPrimary)
                Text(source == .favourites
                     ? "Find spots on the map and\ntap ♥ to save them here."
                     : "Save spots and add them\nto this collection.")
                    .font(.dmSans(15))
                    .foregroundStyle(Color.brandPrimary.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - CollectionSource: Equatable (for empty state icon switch)

extension CollectionSource: Equatable {
    static func == (lhs: CollectionSource, rhs: CollectionSource) -> Bool {
        switch (lhs, rhs) {
        case (.favourites, .favourites): return true
        case (.collection(let a), .collection(let b)): return a.id == b.id
        default: return false
        }
    }
}
