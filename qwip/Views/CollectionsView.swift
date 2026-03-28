import SwiftUI

struct CollectionsView: View {
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(CollectionService.self) var collectionService

    @Environment(AppRouter.self) var appRouter
    @State private var navPath = NavigationPath()

    @State private var showCreateSheet = false
    @State private var editTarget: Collection? = nil
    @State private var deleteTarget: Collection? = nil
    @State private var actionError: String? = nil

    private enum CollectionDestination: Hashable {
        case favourites
        case collection(Collection)
    }

    private var favouriteCount: Int {
        savedSpotService.savedEntries.filter { $0.collectionIds.isEmpty }.count
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if collectionService.isLoading && collectionService.collections.isEmpty
                    && savedSpotService.savedEntries.isEmpty {
                    loadingView
                } else if let error = collectionService.loadError ?? savedSpotService.loadError {
                    errorView(message: error)
                } else {
                    List {
                        // Favourite Spots — pinned first, no swipe
                        NavigationLink(value: CollectionDestination.favourites) {
                            CollectionRow(name: "Favourite Spots", icon: "star.fill",
                                          count: favouriteCount)
                        }

                        // Real collections
                        ForEach(collectionService.collections) { collection in
                            NavigationLink(value: CollectionDestination.collection(collection)) {
                                CollectionRow(name: collection.name, icon: "folder.fill",
                                              count: collection.spotCount,
                                              isShareable: collection.isShareable)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTarget = collection
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editTarget = collection
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationDestination(for: CollectionDestination.self) { destination in
                switch destination {
                case .favourites:
                    CollectionDetailView(source: .favourites)
                case .collection(let collection):
                    CollectionDetailView(source: .collection(collection))
                }
            }
            .onAppear { handlePendingDeepLink() }
            .onChange(of: appRouter.pendingCollectionId) { _, _ in handlePendingDeepLink() }
            .onChange(of: collectionService.collections) { _, _ in handlePendingDeepLink() }
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
                    Button { showCreateSheet = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
            }
            // Create sheet
            .sheet(isPresented: $showCreateSheet) {
                CollectionFormSheet(title: "New Collection") { name, isShareable in
                    Task {
                        do { try await collectionService.create(name: name, isShareable: isShareable) }
                        catch { actionError = error.localizedDescription }
                    }
                }
            }
            // Edit sheet
            .sheet(item: $editTarget) { target in
                CollectionFormSheet(
                    title: "Edit Collection",
                    initialName: target.name,
                    initialShareable: target.isShareable
                ) { name, isShareable in
                    Task {
                        do { try await collectionService.update(id: target.id, name: name, isShareable: isShareable) }
                        catch { actionError = error.localizedDescription }
                    }
                }
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

    // MARK: - Deep link handling

    private func handlePendingDeepLink() {
        guard let id = appRouter.pendingCollectionId,
              let collection = collectionService.collections.first(where: { $0.id == id })
        else { return }
        navPath.append(CollectionDestination.collection(collection))
        appRouter.pendingCollectionId = nil
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
    var isShareable: Bool = false

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
                HStack(spacing: 5) {
                    Text(name)
                        .font(.dmSans(15, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                    if isShareable {
                        Image(systemName: "link")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.brandPrimary.opacity(0.45))
                    }
                }
                Text("\(count) spot\(count == 1 ? "" : "s")")
                    .font(.dmSans(12))
                    .foregroundStyle(Color.brandPrimary.opacity(0.5))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Collection form sheet

struct CollectionFormSheet: View {
    let title: String
    let onSave: (String, Bool) -> Void

    @State private var name: String
    @State private var isShareable: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialName: String = "", initialShareable: Bool = false,
         onSave: @escaping (String, Bool) -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _isShareable = State(initialValue: initialShareable)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Collection name", text: $name)
                        .font(.dmSans(15))
                        .foregroundStyle(Color.brandPrimary)
                        .submitLabel(.done)
                }
                Section {
                    Toggle(isOn: $isShareable) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shareable")
                                .font(.dmSans(15))
                                .foregroundStyle(Color.brandPrimary)
                            Text("Anyone with the link can view this collection")
                                .font(.dmSans(12))
                                .foregroundStyle(Color.brandPrimary.opacity(0.5))
                        }
                    }
                    .tint(Color.brandPrimary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.brandSecondary.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.dmSans(15))
                        .foregroundStyle(Color.brandPrimary.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, isShareable)
                        dismiss()
                    }
                    .font(.dmSans(15, weight: .bold))
                    .foregroundStyle(Color.brandPrimary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.brandSecondary)
    }
}
