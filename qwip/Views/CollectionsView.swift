import SwiftUI

struct CollectionsView: View {
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(CollectionService.self) var collectionService

    @State private var renameTarget: Collection? = nil
    @State private var renameText = ""
    @State private var deleteTarget: Collection? = nil
    @State private var showCreateAlert = false
    @State private var newCollectionName = ""
    @State private var actionError: String? = nil

    private var favouriteCount: Int {
        savedSpotService.savedEntries.filter { $0.collectionIds.isEmpty }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if collectionService.isLoading && collectionService.collections.isEmpty
                    && savedSpotService.savedEntries.isEmpty {
                    loadingView
                } else if let error = collectionService.loadError ?? savedSpotService.loadError {
                    errorView(message: error)
                } else {
                    List {
                        // Favourite Spots — pinned first, no swipe
                        NavigationLink {
                            CollectionDetailView(source: .favourites)
                        } label: {
                            CollectionRow(name: "Favourite Spots", icon: "star.fill",
                                          count: favouriteCount)
                        }

                        // Real collections
                        ForEach(collectionService.collections) { collection in
                            NavigationLink {
                                CollectionDetailView(source: .collection(collection))
                            } label: {
                                CollectionRow(name: collection.name, icon: "folder.fill",
                                              count: collection.spotCount)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTarget = collection
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    renameTarget = collection
                                    renameText = collection.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .refreshable {
                async let s: () = savedSpotService.load()
                async let c: () = collectionService.load()
                _ = await (s, c)
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.large)
            .background(Color.brandSecondary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreateAlert = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
            }
            // Create collection alert
            .alert("New collection", isPresented: $showCreateAlert) {
                TextField("Name", text: $newCollectionName)
                Button("Create") {
                    let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                    newCollectionName = ""
                    guard !name.isEmpty else { return }
                    Task {
                        do { try await collectionService.create(name: name) }
                        catch { actionError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
            // Rename alert
            .alert("Rename collection", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    guard let target = renameTarget else { return }
                    let name = renameText.trimmingCharacters(in: .whitespaces)
                    renameTarget = nil
                    guard !name.isEmpty else { return }
                    Task {
                        do { try await collectionService.rename(id: target.id, name: name) }
                        catch { actionError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            // Delete confirmation
            .confirmationDialog(
                "Delete \"\(deleteTarget?.name ?? "")\"?",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Collection", role: .destructive) {
                    guard let target = deleteTarget else { return }
                    deleteTarget = nil
                    Task {
                        do { try await collectionService.delete(id: target.id) }
                        catch { actionError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("Spots will stay saved.")
            }
            // General action error
            .alert("Error", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK") { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    // MARK: - Loading / error states

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
            Button("Try Again") {
                Task {
                    async let s: () = savedSpotService.load()
                    async let c: () = collectionService.load()
                    _ = await (s, c)
                }
            }
            .font(.dmSans(14, weight: .bold))
            .foregroundStyle(Color.brandPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Collection row

private struct CollectionRow: View {
    let name: String
    let icon: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.brandPrimary.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.dmSans(15, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                Text("\(count) spot\(count == 1 ? "" : "s")")
                    .font(.dmSans(12))
                    .foregroundStyle(Color.brandPrimary.opacity(0.5))
            }
        }
        .padding(.vertical, 4)
    }
}
