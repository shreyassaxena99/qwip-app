import SwiftUI
import MapKit

// A group of one or more spots at a given zoom level
struct SpotCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let spots: [SpotPin]
    var isSingle: Bool { spots.count == 1 }
}

struct MapView: View {
    @Environment(SpotStore.self) var store
    @Environment(LocationService.self) var locationService
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 51.5220, longitude: -0.0950),
            latitudinalMeters: 4500,
            longitudinalMeters: 4500
        )
    )
    @State private var mapSpan = MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
    @State private var selectedSpot: SpotPin? = nil
    @State private var detailSpot: SpotDetail? = nil
    @State private var isFetchingDetail = false
    @State private var detailError: String? = nil
    @State private var hasSetInitialLocation = false
    @State private var showFilters = false
    @AppStorage("mapStyle") private var mapStylePreference = "standard"
    @State private var is3DEnabled: Bool = false
    @State private var mapHeading: Double = 0
    @State private var currentCamera: MapCamera? = nil

    // Group spots into clusters based on current zoom level.
    // Radius scales with span so clusters break apart as you zoom in.
    private var clusters: [SpotCluster] {
        let radius = mapSpan.latitudeDelta * 0.15
        var remaining = store.filteredSpots
        var result: [SpotCluster] = []
        while !remaining.isEmpty {
            let anchor = remaining.removeFirst()
            var group = [anchor]
            remaining = remaining.filter { spot in
                let dLat = abs(spot.coordinate.latitude - anchor.coordinate.latitude)
                let dLng = abs(spot.coordinate.longitude - anchor.coordinate.longitude)
                if dLat < radius && dLng < radius {
                    group.append(spot)
                    return false
                }
                return true
            }
            let lat = group.map(\.coordinate.latitude).reduce(0, +) / Double(group.count)
            let lng = group.map(\.coordinate.longitude).reduce(0, +) / Double(group.count)
            result.append(SpotCluster(
                id: group.map(\.id).sorted().joined(separator: "-"),
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                spots: group
            ))
        }
        return result
    }

    private func zoomToCluster(_ cluster: SpotCluster) {
        let spots = cluster.spots

        // Compute all pairwise separations. Clustering uses dLat < radius && dLng < radius,
        // so the binding constraint per pair is max(dLat, dLng).
        var separations: [Double] = []
        for i in 0..<spots.count {
            for j in (i+1)..<spots.count {
                let dLat = abs(spots[i].coordinate.latitude - spots[j].coordinate.latitude)
                let dLng = abs(spots[i].coordinate.longitude - spots[j].coordinate.longitude)
                separations.append(max(dLat, dLng))
            }
        }
        separations.sort()

        guard !separations.isEmpty else { return }

        // Targeting the median separation means roughly half the pairs remain within
        // clustering radius after the zoom — naturally halving the cluster each tap.
        // To break smaller clusters in one tap, lower this fraction toward 0.
        // To be more aggressive on large clusters, raise it toward 1.
        let splitFraction = 0.5
        let targetIndex = Int(Double(separations.count) * splitFraction)
        let targetSeparation = separations[min(targetIndex, separations.count - 1)]

        // Set span so radius lands at 70% of the target separation for a clean split.
        let targetDelta = max((targetSeparation / 0.15) * 0.7, 0.002)
        let aspectRatio = mapSpan.longitudeDelta / mapSpan.latitudeDelta
        let span = MKCoordinateSpan(
            latitudeDelta: targetDelta,
            longitudeDelta: targetDelta * aspectRatio
        )
        withAnimation(.easeInOut(duration: 0.5)) {
            position = .region(MKCoordinateRegion(center: cluster.coordinate, span: span))
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            filterBarOverlay
            mapControlsOverlay
            selectedSpotPreview
            if store.isLoading && store.spots.isEmpty {
                loadingOverlay
            }
        }
        .task {
            locationService.requestAuthorization()
            await store.loadSpots()
        }
        .onChange(of: locationService.userLocation) { _, location in
            guard let location, !hasSetInitialLocation else { return }
            hasSetInitialLocation = true
            withAnimation(.easeInOut(duration: 0.8)) {
                position = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 4500,
                    longitudinalMeters: 4500
                ))
            }
        }
        .sheet(item: $detailSpot) { detail in
            SpotDetailView(detail: detail)
        }
        .sheet(isPresented: $showFilters) {
            FiltersSheet()
                .environment(store)
        }
        .alert("Couldn't load spots", isPresented: Binding(
            get: { store.loadError != nil },
            set: { if !$0 { store.loadError = nil } }
        )) {
            Button("Retry") { Task { await store.loadSpots() } }
            Button("Cancel", role: .cancel) { store.loadError = nil }
        } message: {
            Text(store.loadError ?? "")
        }
        .alert("Error", isPresented: Binding(
            get: { detailError != nil },
            set: { if !$0 { detailError = nil } }
        )) {
            Button("OK") { detailError = nil }
        } message: {
            Text(detailError ?? "")
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(clusters) { cluster in
                if cluster.spots.count <= 2 {
                    ForEach(cluster.spots) { spot in
                        Annotation("", coordinate: spot.coordinate, anchor: .bottom) {
                            SpotAnnotationView(spot: spot, isSelected: selectedSpot?.id == spot.id)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        if selectedSpot?.id == spot.id {
                                            selectedSpot = nil
                                        } else {
                                            selectedSpot = spot
                                            isFetchingDetail = false
                                        }
                                    }
                                }
                        }
                    }
                } else {
                    Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                        ClusterAnnotationView(count: cluster.spots.count)
                            .onTapGesture {
                                withAnimation { selectedSpot = nil }
                                zoomToCluster(cluster)
                            }
                    }
                }
            }
        }
        .mapStyle(
            mapStylePreference == "hybrid"
                ? .hybrid(elevation: is3DEnabled ? .realistic : .flat, pointsOfInterest: .excludingAll, showsTraffic: false)
                : .standard(elevation: is3DEnabled ? .realistic : .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)
        )
        .onMapCameraChange(frequency: .onEnd) { context in
            currentCamera = context.camera
            mapSpan = context.region.span
            // Clear selected spot if it's now merged into a cluster
            if let selected = selectedSpot {
                let visible = clusters.contains { $0.spots.count <= 2 && $0.spots.contains { $0.id == selected.id } }
                if !visible { withAnimation { selectedSpot = nil } }
            }
        }
        .onMapCameraChange(frequency: .continuous) { context in
            let newHeading = context.camera.heading
            if (abs(newHeading) > 0.5) != (abs(mapHeading) > 0.5) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    mapHeading = newHeading
                }
            } else {
                mapHeading = newHeading
            }
        }
        .ignoresSafeArea()
        .onTapGesture {
            withAnimation { selectedSpot = nil }
        }
    }

    // MARK: - Filter Bar

    private var filterBarOverlay: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        FilterPill(title: "All", isActive: store.selectedCategory == nil) {
                            store.selectedCategory = nil
                        }
                        ForEach(SpotCategory.allCases) { category in
                            FilterPill(
                                title: category.displayName,
                                icon: category.systemIcon,
                                isActive: store.selectedCategory == category
                            ) {
                                store.selectedCategory = (store.selectedCategory == category) ? nil : category
                            }
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .padding(.vertical, 9)
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 22)

            Button { showFilters = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .bold))
                    if store.additionalFilterCount > 0 {
                        Text("\(store.additionalFilterCount)")
                            .font(.dmSans(9, weight: .black))
                            .foregroundStyle(Color.brandSecondary)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color.brandPrimary))
                    }
                }
                .foregroundStyle(
                    store.additionalFilterCount > 0 ? Color.brandPrimary : Color.primary.opacity(0.55)
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: store.additionalFilterCount)
        }
        .glassEffect(in: .capsule)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Map Controls

    private var mapControlsOverlay: some View {
        VStack {
            HStack {
                Spacer()
                GlassEffectContainer(spacing: 0) {
                    VStack(spacing: 0) {
                        // Location button
                        Button(action: snapToUserLocation) {
                            Image("ic_navigation")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 17, height: 17)
                                .foregroundStyle(Color.primary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)

                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: 22, height: 1)

                        // 3D toggle button
                        Button(action: toggle3D) {
                            Image("ic_box")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 17, height: 17)
                                .foregroundStyle(is3DEnabled ? Color.brandSecondary : Color.primary)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(is3DEnabled ? Color.brandPrimary : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: is3DEnabled)

                        // Compass — only visible when map is rotated from north
                        if abs(mapHeading) > 0.5 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.12))
                                .frame(width: 22, height: 1)
                                .transition(.opacity)

                            Button(action: resetNorth) {
                                Image(systemName: "safari")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(Color.primary)
                                    // Counter-rotate by heading so the needle always points to geographic north
                                    .rotationEffect(.degrees(-mapHeading))
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                        }
                    }
                    .padding(5)
                }
                .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.trailing, 11)
            }
            Spacer()
        }
        .padding(.top, 80)
    }

    // MARK: - Selected Spot Preview

    private var selectedSpotPreview: some View {
        VStack {
            Spacer()
            if let spot = selectedSpot {
                selectedSpotTile(spot)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
    }

    private func selectedSpotTile(_ spot: SpotPin) -> some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color.brandPrimary.opacity(0.06))
                .frame(width: 120)
                .offset(x: 30, y: -30)
                .blur(radius: 16)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.brandPrimary)
                            .frame(width: 50, height: 50)
                        Image(systemName: spot.category.systemIcon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.brandSecondary)
                    }
                    .shadow(color: Color.brandPrimary.opacity(0.4), radius: 8, x: 0, y: 3)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(spot.name)
                            .font(.dmSans(18, weight: .heavy))
                            .foregroundStyle(Color.brandPrimary)
                            .lineLimit(1)
                        Text(spot.category.displayName.uppercased())
                            .font(.dmSans(9, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(Color.brandPrimary.opacity(0.5))
                        if let address = spot.shortAddress {
                            Text(address)
                                .font(.dmSans(11, weight: .medium))
                                .foregroundStyle(Color.brandPrimary.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    OpenBadge(isOpen: spot.isOpenNow)
                }

                HStack(spacing: 0) {
                    statChip(icon: "star.fill", iconColor: .orange, value: spot.formattedRating, label: "RATING")
                    if let noise = spot.noiseMatrix?.currentLevel() {
                        dividerLine()
                        statChip(icon: noise.systemIcon, iconColor: Color.brandPrimary, value: noise.displayName, label: "USUALLY")
                    }
                    if spot.wifiAvailable {
                        dividerLine()
                        statChip(icon: "wifi", iconColor: Color.brandPrimary, value: "Wi-Fi", label: "AVAIL")
                    }
                }
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.brandPrimary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.brandPrimary.opacity(0.1), lineWidth: 1)
                        )
                )

                Button {
                    guard !isFetchingDetail else { return }
                    Task {
                        isFetchingDetail = true
                        do {
                            detailSpot = try await SpotAPIClient.shared.fetchSpotDetail(id: spot.id)
                        } catch SpotAPIError.notFound {
                            detailError = "This spot is no longer available."
                        } catch {
                            detailError = error.localizedDescription
                        }
                        isFetchingDetail = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isFetchingDetail {
                            ProgressView()
                                .tint(Color.brandSecondary)
                        } else {
                            Text("View Spot")
                                .font(.dmSans(15, weight: .black))
                                .tracking(0.3)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .foregroundStyle(Color.brandSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.brandPrimary.opacity(0.4), radius: 10, x: 0, y: 4)
                }
            }
            .padding(18)
        }
        .background(glassBackground(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.brandPrimary.opacity(0.14), radius: 24, x: 0, y: 8)
        .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Color.brandSecondary)
                Text("Loading spots…")
                    .font(.dmSans(13, weight: .semibold))
                    .foregroundStyle(Color.brandSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.brandPrimary.opacity(0.92))
            .clipShape(Capsule())
            .shadow(color: Color.brandPrimary.opacity(0.3), radius: 12, x: 0, y: 4)
            .padding(.bottom, 110)
        }
    }

    // MARK: - Helpers

    private func statChip(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.dmSans(12, weight: .heavy))
                .foregroundStyle(Color.brandPrimary)
                .lineLimit(1)
            Text(label)
                .font(.dmSans(7, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Color.brandPrimary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func dividerLine() -> some View {
        Rectangle()
            .fill(Color.brandPrimary.opacity(0.12))
            .frame(width: 1, height: 32)
    }

    private func snapToUserLocation() {
        guard let location = locationService.userLocation else { return }
        withAnimation(.easeInOut(duration: 0.8)) {
            position = .region(MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            ))
        }
    }

    private func toggle3D() {
        let enabling = !is3DEnabled
        is3DEnabled = enabling
        guard let cam = currentCamera else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            position = .camera(MapCamera(
                centerCoordinate: cam.centerCoordinate,
                distance: cam.distance,
                heading: cam.heading,
                pitch: enabling ? 45 : 0
            ))
        }
    }

    private func resetNorth() {
        guard let cam = currentCamera else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            position = .camera(MapCamera(
                centerCoordinate: cam.centerCoordinate,
                distance: cam.distance,
                heading: 0,
                pitch: cam.pitch
            ))
        }
    }
}

// MARK: - Cluster Annotation

private struct ClusterAnnotationView: View {
    let count: Int
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .fill(Color.brandPrimary.opacity(0.18))
                .frame(width: 56, height: 56)

            // Main circle
            Circle()
                .fill(Color.brandPrimary)
                .frame(width: 44, height: 44)
                .shadow(color: Color.brandPrimary.opacity(0.45), radius: 8, x: 0, y: 3)

            // Border
            Circle()
                .stroke(Color.brandSecondary.opacity(0.35), lineWidth: 1.5)
                .frame(width: 44, height: 44)

            Text("\(count)")
                .font(.dmSans(15, weight: .black))
                .foregroundStyle(Color.brandSecondary)
        }
        .scaleEffect(appeared ? 1.0 : 0.4)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                appeared = true
            }
        }
    }
}

// MARK: - Filters Sheet

private struct FiltersSheet: View {
    @Environment(SpotStore.self) var store
    @Environment(CollectionService.self) var collectionService
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(\.dismiss) var dismiss

    @State private var selectedCollectionId: String? = nil

    var body: some View {
        @Bindable var bindableStore = store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Collections
                    if !collectionService.collections.isEmpty {
                        filterSection("Collection") {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.brandPrimary)
                                    .frame(width: 22)
                                Text("Show spots from")
                                    .font(.dmSans(14, weight: .bold))
                                    .foregroundStyle(Color.brandPrimary)
                                Spacer()
                                Menu {
                                    Button("Any") { selectedCollectionId = nil }
                                    ForEach(collectionService.collections) { c in
                                        Button(c.name) { selectedCollectionId = c.id }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(collectionService.collections.first(where: { $0.id == selectedCollectionId })?.name ?? "Any")
                                            .font(.dmSans(14, weight: .bold))
                                            .foregroundStyle(Color.brandPrimary)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.brandPrimary.opacity(0.5))
                                    }
                                    .fixedSize()
                                }
                            }
                            .padding(16)
                            .background(glassBackground(cornerRadius: 18))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }

                    // Quick Filters
                    filterSection("Quick Filters") {
                        VStack(spacing: 0) {
                            filterRow(
                                icon: "clock.fill",
                                label: "Open Now",
                                isOn: $bindableStore.filterOpenNow
                            )
                            Divider()
                                .overlay(Color.brandPrimary.opacity(0.08))
                                .padding(.horizontal, 16)
                            filterRow(
                                icon: "wifi",
                                label: "Wi-Fi Available",
                                isOn: $bindableStore.filterWifi
                            )
                        }
                        .background(glassBackground(cornerRadius: 18))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    // Noise Level
                    filterSection("Noise Level") {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach([NoiseLevel.quiet, .moderate, .lively], id: \.self) { level in
                                    NoisePill(
                                        label: level.displayName,
                                        icon: level.systemIcon,
                                        isActive: store.filterNoiseLevel == level
                                    ) {
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                            store.filterNoiseLevel = (store.filterNoiseLevel == level) ? nil : level
                                        }
                                    }
                                }
                            }
                            NoisePill(label: "Any", icon: nil, isActive: store.filterNoiseLevel == nil) {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                    store.filterNoiseLevel = nil
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 8)
            }
            .background(Color.brandSecondary.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") {
                        withAnimation { store.clearAdditionalFilters() }
                    }
                    .font(.dmSans(14))
                    .foregroundStyle(
                        store.hasAdditionalFilters
                            ? Color.brandPrimary.opacity(0.6)
                            : Color.brandPrimary.opacity(0.25)
                    )
                    .disabled(!store.hasAdditionalFilters)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dmSans(14, weight: .bold))
                        .foregroundStyle(Color.brandPrimary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.brandSecondary)
        .onAppear { selectedCollectionId = store.filterCollectionId }
        .onChange(of: selectedCollectionId) { _, newId in
            if let id = newId {
                let spotIds = Set(
                    savedSpotService.savedEntries
                        .filter { $0.collectionIds.contains(id) }
                        .map { $0.spot.id }
                )
                store.setCollectionFilter(id: id, spotIds: spotIds)
            } else {
                store.clearCollectionFilter()
            }
        }
    }

    private func filterSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.dmSans(10, weight: .black))
                .tracking(1.2)
                .foregroundStyle(Color.brandPrimary.opacity(0.5))
            content()
        }
    }

    private func filterRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 22)
            Text(label)
                .font(.dmSans(14, weight: .bold))
                .foregroundStyle(Color.brandPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.brandPrimary)
        }
        .padding(16)
    }
}

// MARK: - Noise Pill

private struct NoisePill: View {
    let label: String
    let icon: String?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                }
                Text(label)
                    .font(.dmSans(12, weight: .bold))
            }
            .foregroundStyle(isActive ? Color.brandSecondary : Color.brandPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isActive ? Color.brandPrimary : Color.brandPrimary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.brandPrimary.opacity(isActive ? 0 : 0.12), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isActive)
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let title: String
    var icon: String? = nil
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        if isActive {
            pill.glassEffect(in: .capsule)
        } else {
            pill
        }
    }

    private var pill: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title.uppercased())
                    .font(.dmSans(10, weight: .black))
                    .tracking(0.5)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
