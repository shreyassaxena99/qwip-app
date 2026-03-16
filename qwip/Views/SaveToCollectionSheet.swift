import SwiftUI

struct SaveToCollectionSheet: View {
    let spot: SpotPin
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(CollectionService.self) var collectionService
    @Environment(\.dismiss) var dismiss

    @State private var selectedIds: Set<String> = []
    @State private var favouritesTicked = true
    @State private var isNewCollectionExpanded = false
    @State private var newCollectionName = ""
    @State private var isSaving = false
    @State private var error: String? = nil

    // Snapshot of collection IDs when sheet opened (for diffing on "Done")
    @State private var originalCollectionIds: [String] = []

    private var isSaved: Bool { savedSpotService.isSaved(spot.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Drag handle
                    Capsule()
                        .fill(Color.brandPrimary.opacity(0.2))
                        .frame(width: 36, height: 4)
                        .padding(.top, 12)
                        .padding(.bottom, 24)

                    // Collections list
                    VStack(spacing: 0) {
                        // Favourite Spots (virtual — always first, no swipe)
                        collectionRow(
                            name: "Favourite Spots",
                            icon: "star.fill",
                            isSelected: favouritesTicked
                        ) {
                            favouritesTicked.toggle()
                        }

                        // Real collections
                        ForEach(collectionService.collections) { collection in
                            Divider()
                                .padding(.leading, 58)
                                .overlay(Color.brandPrimary.opacity(0.08))
                            collectionRow(
                                name: collection.name,
                                icon: "folder.fill",
                                isSelected: selectedIds.contains(collection.id)
                            ) {
                                if selectedIds.contains(collection.id) {
                                    selectedIds.remove(collection.id)
                                } else {
                                    selectedIds.insert(collection.id)
                                    // Untick Favourites when a real collection is ticked
                                    favouritesTicked = false
                                }
                            }
                        }

                        // New collection
                        Divider()
                            .padding(.leading, 58)
                            .overlay(Color.brandPrimary.opacity(0.08))
                        if isNewCollectionExpanded {
                            newCollectionField
                        } else {
                            newCollectionButton
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                    .background(glassBackground(cornerRadius: 18))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 20)

                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            confirm()
                        } label: {
                            Group {
                                if isSaving {
                                    ProgressView().tint(Color.brandSecondary)
                                } else {
                                    Text(isSaved ? "Done" : "Save")
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

                        if isSaved {
                            Button(role: .destructive) {
                                removeFromSaved()
                            } label: {
                                Text("Remove from saved")
                                    .font(.dmSans(14, weight: .semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.brandSecondary.ignoresSafeArea())
            .navigationTitle(isSaved ? "Organise" : "Save to collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().stroke(Color.brandPrimary.opacity(0.12), lineWidth: 1))
                                .frame(width: 32, height: 32)
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                }
            }
            .alert("Couldn't save", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onAppear { loadInitialState() }
    }

    // MARK: - Subviews

    private func collectionRow(name: String, icon: String, isSelected: Bool,
                               onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.brandPrimary.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                }
                Text(name)
                    .font(.dmSans(15, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.brandPrimary.opacity(isSelected ? 0 : 0.25), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.brandPrimary)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.brandSecondary)
                    }
                }
                .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newCollectionButton: some View {
        Button {
            withAnimation(.spring(response: 0.3)) { isNewCollectionExpanded = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.brandPrimary.opacity(0.05))
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary.opacity(0.45))
                }
                Text("New collection")
                    .font(.dmSans(15, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary.opacity(0.45))
                Spacer()
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newCollectionField: some View {
        HStack(spacing: 12) {
            TextField("Collection name", text: $newCollectionName)
                .font(.dmSans(15))
                .foregroundStyle(Color.brandPrimary)
                .padding(.vertical, 14)
            Button("Create") {
                createCollection()
            }
            .font(.dmSans(14, weight: .bold))
            .foregroundStyle(Color.brandPrimary)
            .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Actions

    private func loadInitialState() {
        if isSaved {
            let ids = savedSpotService.savedEntries.first(where: { $0.id == spot.id })?.collectionIds ?? []
            originalCollectionIds = ids
            selectedIds = Set(ids)
            favouritesTicked = ids.isEmpty
        } else {
            originalCollectionIds = []
            selectedIds = []
            favouritesTicked = true
        }
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                let created = try await collectionService.create(name: name)
                selectedIds.insert(created.id)
                favouritesTicked = false
                withAnimation { isNewCollectionExpanded = false }
                newCollectionName = ""
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func confirm() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if isSaved {
                    let original = Set(originalCollectionIds)
                    let added = selectedIds.subtracting(original)
                    let removed = original.subtracting(selectedIds)
                    for id in added {
                        _ = try await collectionService.addSpot(spotId: spot.id, toCollection: id)
                    }
                    for id in removed {
                        try await collectionService.removeSpot(spotId: spot.id, fromCollection: id)
                    }
                    // selectedIds contains only real collection IDs;
                    // empty set correctly means the spot returns to Favourite Spots
                    savedSpotService.updateCollectionIds(spotId: spot.id, collectionIds: Array(selectedIds))
                } else {
                    try await savedSpotService.save(spot: spot, collectionIds: Array(selectedIds))
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func removeFromSaved() {
        Task {
            do {
                try await savedSpotService.unsave(spotId: spot.id)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
