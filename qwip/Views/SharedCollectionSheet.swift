import SwiftUI

struct SharedCollectionSheet: View {
    let collectionId: String

    @Environment(CollectionService.self) var collectionService
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(AppRouter.self) var appRouter

    @State private var collection: SharedCollection? = nil
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var detailSpot: SpotDetail? = nil
    @State private var fetchingDetailID: String? = nil
    @State private var fetchDetailError: String? = nil

    // Save as copy
    @State private var showingSaveCopyAlert = false
    @State private var copyName = ""
    @State private var isSaving = false
    @State private var saveError: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let error = loadError {
                    errorView(message: error)
                } else if let collection {
                    contentView(collection: collection)
                }
            }
            .navigationTitle(collection?.name ?? "")
            .navigationBarTitleDisplayMode(.large)
            .background(Color.brandSecondary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { appRouter.pendingSharedCollectionId = nil } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().stroke(Color.brandBorder, lineWidth: 1))
                                .frame(width: 40, height: 40)
                            Image("ic_x")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 17, height: 17)
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await load() }
        .sheet(item: $detailSpot) { detail in
            SpotDetailView(detail: detail)
        }
        .alert("Couldn't load spot", isPresented: Binding(
            get: { fetchDetailError != nil },
            set: { if !$0 { fetchDetailError = nil } }
        )) {
            Button("OK") { fetchDetailError = nil }
        } message: {
            Text(fetchDetailError ?? "")
        }
        .alert("Save as copy", isPresented: $showingSaveCopyAlert) {
            TextField("Collection name", text: $copyName)
            Button("Save") { Task { await saveAsCopy() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentView(collection: SharedCollection) -> some View {
        ZStack(alignment: .bottom) {
            List {
                if let desc = collection.collectionDescription, !desc.isEmpty {
                    Section {
                        Text(desc)
                            .font(.dmSans(14))
                            .foregroundStyle(Color.brandPrimary.opacity(0.55))
                            .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.brandSecondary)
                    .listRowSeparator(.hidden)
                }

                Section {
                    ForEach(collection.spots) { spot in
                        SpotRow(spot: spot)
                            .contentShape(Rectangle())
                            .onTapGesture { fetchDetail(for: spot) }
                            .overlay(alignment: .trailing) {
                                if fetchingDetailID == spot.id {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .padding(.trailing, 16)
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 90) }

            // Sticky save button with fade-in gradient
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.brandSecondary.opacity(0), Color.brandSecondary],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 24)
                .allowsHitTesting(false)

                Button {
                    copyName = "Copy of \(collection.name)"
                    showingSaveCopyAlert = true
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(Color.brandSecondary)
                        } else {
                            Text("Save as copy")
                                .font(.dmSans(15, weight: .heavy))
                                .foregroundStyle(Color.brandSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.brandPrimary)
                    )
                }
                .disabled(isSaving)
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .background(Color.brandSecondary)
            }
        }
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack {
            Spacer(minLength: 120)
            ProgressView().scaleEffect(1.2).tint(Color.brandPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 120)
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.brandPrimary.opacity(0.4))
            Text(message)
                .font(.dmSans(14))
                .foregroundStyle(Color.brandPrimary.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") { Task { await load() } }
                .font(.dmSans(14, weight: .bold))
                .foregroundStyle(Color.brandPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            collection = try await CollectionAPIClient.shared.fetchShared(id: collectionId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func fetchDetail(for spot: SpotPin) {
        guard fetchingDetailID == nil else { return }
        Task {
            fetchingDetailID = spot.id
            do {
                detailSpot = try await SpotAPIClient.shared.fetchSpotDetail(id: spot.id)
            } catch SpotAPIError.notFound {
                fetchDetailError = "This spot is no longer available."
            } catch {
                fetchDetailError = error.localizedDescription
            }
            fetchingDetailID = nil
        }
    }

    // MARK: - Save as copy

    private func saveAsCopy() async {
        guard let collection else { return }
        let name = copyName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSaving = true
        do {
            // Create the new collection (optimistic — immediately appears in collectionService.collections)
            let created = try await collectionService.create(name: name)

            // Add each spot; also saves any unsaved spots as a side-effect
            for spot in collection.spots {
                _ = try await CollectionAPIClient.shared.addSpotToCollection(
                    collectionId: created.id, spotId: spot.id)
            }

            // Refresh both services so saved state + collection spot count are accurate
            async let savedLoad: () = savedSpotService.load()
            async let collectionsLoad: () = collectionService.load()
            _ = await (savedLoad, collectionsLoad)

            // Dismiss this sheet, then navigate to the new collection via the existing deep-link path
            appRouter.pendingSharedCollectionId = nil
            appRouter.pendingCollectionId = created.id
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}
