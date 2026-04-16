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
        case collection(Collection)
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if collectionService.isLoading && collectionService.collections.isEmpty {
                    loadingView
                } else if let error = collectionService.loadError ?? savedSpotService.loadError {
                    errorView(message: error)
                } else {
                    List {
                        // Default collection (Favourite Spots) — pinned first, no swipe actions
                        if let defaultCollection = collectionService.collections.first(where: { $0.isDefault }) {
                            NavigationLink(value: CollectionDestination.collection(defaultCollection)) {
                                CollectionRow(name: defaultCollection.name, icon: "star.fill",
                                              count: savedSpotService.savedEntries.count)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(.init(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }

                        // Custom collections
                        ForEach(collectionService.collections.filter { !$0.isDefault }) { collection in
                            NavigationLink(value: CollectionDestination.collection(collection)) {
                                CollectionRow(name: collection.name, icon: "folder.fill",
                                              count: collection.spotCount,
                                              isShareable: collection.isShareable,
                                              description: collection.collectionDescription)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(.init(top: 4, leading: 16, bottom: 4, trailing: 16))
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
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationDestination(for: CollectionDestination.self) { destination in
                switch destination {
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
                CollectionFormSheet(title: "New Collection") { name, description, isShareable in
                    Task {
                        do { try await collectionService.create(name: name, collectionDescription: description, isShareable: isShareable) }
                        catch { actionError = error.localizedDescription }
                    }
                }
            }
            // Edit sheet
            .sheet(item: $editTarget) { target in
                CollectionFormSheet(
                    title: "Edit Collection",
                    initialName: target.name,
                    initialDescription: target.collectionDescription ?? "",
                    initialShareable: target.isShareable
                ) { name, description, isShareable in
                    Task {
                        do { try await collectionService.update(id: target.id, name: name, collectionDescription: description, isShareable: isShareable) }
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
        guard let id = appRouter.pendingCollectionId else { return }

        // Own collection — navigate directly (existing behaviour)
        if let collection = collectionService.collections.first(where: { $0.id == id }) {
            navPath.append(CollectionDestination.collection(collection))
            appRouter.pendingCollectionId = nil
            return
        }

        // Collections still loading — wait for the onChange(of: collectionService.collections) trigger
        guard !collectionService.isLoading else { return }

        // Not the user's collection — hand off to the shared collection sheet
        appRouter.pendingSharedCollectionId = id
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
    var description: String? = nil

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
                if let description, !description.isEmpty {
                    Text(description)
                        .font(.dmSans(12))
                        .foregroundStyle(Color.brandPrimary.opacity(0.5))
                        .lineLimit(1)
                } else {
                    Text("\(count) spot\(count == 1 ? "" : "s")")
                        .font(.dmSans(12))
                        .foregroundStyle(Color.brandPrimary.opacity(0.5))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassBackground(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Collection form sheet

struct CollectionFormSheet: View {
    let title: String
    let onSave: (String, String?, Bool) -> Void

    @State private var name: String
    @State private var descriptionText: String
    @State private var isShareable: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialName: String = "", initialDescription: String = "",
         initialShareable: Bool = false, onSave: @escaping (String, String?, Bool) -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _descriptionText = State(initialValue: initialDescription)
        _isShareable = State(initialValue: initialShareable)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Collection name", text: $name)
                        .font(.dmSans(15))
                        .foregroundStyle(Color.brandPrimary)
                        .submitLabel(.next)
                }
                Section {
                    TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.dmSans(15))
                        .foregroundStyle(Color.brandPrimary)
                        .onChange(of: descriptionText) { _, new in
                            if new.count > 500 { descriptionText = String(new.prefix(500)) }
                        }
                    if !descriptionText.isEmpty {
                        Text("\(descriptionText.count) / 500")
                            .font(.dmSans(11))
                            .foregroundStyle(Color.brandPrimary.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
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
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmedName.isEmpty else { return }
                        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmedName, trimmedDesc.isEmpty ? nil : trimmedDesc, isShareable)
                        dismiss()
                    }
                    .font(.dmSans(15, weight: .bold))
                    .foregroundStyle(Color.brandPrimary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.brandSecondary)
    }
}
