import SwiftUI
import MapKit
import Supabase
import OSLog

private let podOccupancyLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "qwip",
                                     category: "PodOccupancy")

// A group of one or more spots at a given zoom level
struct SpotCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let spots: [SpotPin]
    var isSingle: Bool { spots.count == 1 }
}

private struct PodMapLocation: Identifiable {
    let pod: ReservablePod
    let coordinate: CLLocationCoordinate2D
    var id: String { pod.id }
}

private struct PodOccupancy: Decodable {
    let id: String
    let inUse: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case inUse = "in_use"
    }
}

struct MapView: View {
    @Environment(AuthService.self) private var authService
    @Environment(SpotStore.self) var store
    @Environment(LocationService.self) var locationService
    @Environment(SearchViewModel.self) var searchViewModel
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(\.scenePhase) private var scenePhase
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 51.5220, longitude: -0.0950),
            latitudinalMeters: 4500,
            longitudinalMeters: 4500
        )
    )
    @State private var mapSpan = MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
    @State private var selectedSpot: SpotPin? = nil
    @State private var podLocations: [PodMapLocation] = []
    @State private var podInUse: [String: Bool] = [:]
    @State private var selectedPod: ReservablePod? = nil
    @State private var bookingPod: ReservablePod? = nil
    @State private var podLoadError: String? = nil
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
        // Apply search radius filter on top of store's category/preference filters
        let source: [SpotPin]
        if let place = searchViewModel.selectedPlace, let radiusMetres = searchViewModel.selectedRadius {
            let placeLocation = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            source = store.filteredSpots.filter { spot in
                let spotLocation = CLLocation(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude)
                return spotLocation.distance(from: placeLocation) <= radiusMetres
            }
        } else {
            source = store.filteredSpots
        }

        let radius = mapSpan.latitudeDelta * 0.15
        var remaining = source
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
            selectedPlacePreview
            if store.isLoading && store.spots.isEmpty {
                loadingOverlay
            }
        }
        .task {
            locationService.requestAuthorization()
            await store.loadSpots()
        }
        .task(id: authService.session?.user.id) {
            await loadPodLocations()
        }
        .task(id: authService.session?.user.id) { await watchPodOccupancy() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshPodOccupancy() } }
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
            SpotDetailView(detail: detail,
                           livePodInUse: detail.podId.flatMap { podInUse[$0] })
        }
        .sheet(item: $bookingPod) { pod in
            NavigationStack { PodBookingView(pod: pod) }
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
        .alert("Couldn't load pods", isPresented: Binding(
            get: { podLoadError != nil },
            set: { if !$0 { podLoadError = nil } }
        )) {
            Button("Retry") { Task { await loadPodLocations() } }
            Button("Cancel", role: .cancel) { podLoadError = nil }
        } message: {
            Text(podLoadError ?? "")
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
                                    let isSelecting = selectedSpot?.id != spot.id
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedPod = nil
                                        if selectedSpot?.id == spot.id {
                                            selectedSpot = nil
                                        } else {
                                            selectedSpot = spot
                                            isFetchingDetail = false
                                        }
                                    }
                                    if isSelecting {
                                        if let cam = currentCamera {
                                            withAnimation(.easeOut(duration: 0.5)) {
                                                position = .camera(MapCamera(
                                                    centerCoordinate: spot.coordinate,
                                                    distance: cam.distance,
                                                    heading: cam.heading,
                                                    pitch: cam.pitch
                                                ))
                                            }
                                        } else {
                                            withAnimation(.easeOut(duration: 0.5)) {
                                                position = .region(MKCoordinateRegion(center: spot.coordinate, span: mapSpan))
                                            }
                                        }
                                    }
                                }
                        }
                    }
                } else {
                    Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                        ClusterAnnotationView(count: cluster.spots.count)
                            .onTapGesture {
                                withAnimation { selectedSpot = nil; selectedPod = nil }
                                zoomToCluster(cluster)
                            }
                    }
                }
            }
            ForEach(podLocations) { location in
                Annotation("", coordinate: location.coordinate, anchor: .bottom) {
                    PodAnnotationView(isSelected: selectedPod?.id == location.pod.id)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedPod = location.pod
                                selectedSpot = nil
                            }
                        }
                }
            }
            if let place = searchViewModel.selectedPlace, let radius = searchViewModel.selectedRadius {
                MapCircle(center: place.coordinate, radius: radius)
                    .foregroundStyle(Color.brandPrimary.opacity(0.07))
                    .stroke(Color.brandPrimary.opacity(0.35), lineWidth: 1.5)
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
            withAnimation { selectedSpot = nil; selectedPod = nil }
        }
        .onChange(of: searchViewModel.selectedRadius) { _, radius in
            guard let radius, let place = searchViewModel.selectedPlace else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
                position = .region(MKCoordinateRegion(
                    center: place.coordinate,
                    latitudinalMeters: radius * 2.4,
                    longitudinalMeters: radius * 2.4
                ))
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBarOverlay: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        if searchViewModel.selectedPlace != nil {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    searchViewModel.clearSearch()
                                    selectedSpot = nil
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Clear")
                                        .font(.dmSans(10, weight: .black))
                                        .tracking(0.5)
                                }
                                .foregroundStyle(Color.brandSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.brandPrimary))
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                        FilterPill(title: "All", isActive: store.selectedCategory == nil) {
                            store.selectedCategory = nil
                        }
                        ForEach(SpotCategory.allCases) { category in
                            FilterPill(
                                title: category.displayName,
                                icon: category.iconName,
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
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 28)
                    Rectangle()
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 28)
                }
            )

            Rectangle()
                .fill(Color.brandBorder)
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
                            .fill(Color.brandBorder)
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
                                .fill(Color.brandBorder)
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

    // MARK: - Selected Place Preview

    private var selectedPlacePreview: some View {
        VStack {
            Spacer()
            if let pod = selectedPod {
                selectedPodTile(pod)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            } else if let spot = selectedSpot {
                selectedSpotTile(spot)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
    }

    private func selectedPodTile(_ pod: ReservablePod) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image("ic_pod_door")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(hex: "1F3D32"))
                    .frame(width: 25, height: 25)
                    .frame(width: 50, height: 50)
                    .background(Color.brandTerracotta, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text(pod.name).font(.dmSans(18, weight: .heavy))
                    Text("qwip pod")
                        .font(.dmSans(9, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(Color.brandPrimary)
                    Text(pod.address)
                        .font(.dmSans(11, weight: .medium))
                        .foregroundStyle(Color.brandPrimary.opacity(0.55))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                PodOccupancyBadge(inUse: podInUse[pod.id] ??
                    store.spots.first(where: { $0.podId == pod.id })?.isInUse)
            }
            Button { bookingPod = pod } label: {
                Text("Reserve pod")
                    .font(.dmSans(15, weight: .black))
                    .foregroundStyle(Color.brandSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(glassBackground(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
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
                        Image(spot.category.iconName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
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
                    VStack(alignment: .trailing, spacing: 8) {
                        if spot.category == .pod {
                            PodOccupancyBadge(inUse: spot.podId.flatMap { podInUse[$0] } ?? spot.isInUse)
                        } else {
                            OpenBadge(isOpen: spot.isOpenNow)
                        }
                        Button {
                            Task {
                                if savedSpotService.isSaved(spot.id) {
                                    try? await savedSpotService.unsave(spotId: spot.id)
                                } else {
                                    try? await savedSpotService.save(spot: spot)
                                }
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().stroke(Color.brandBorder, lineWidth: 1))
                                    .frame(width: 32, height: 32)
                                Image("ic_heart")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 13, height: 13)
                                    .foregroundStyle(savedSpotService.isSaved(spot.id) ? Color(hex: "e74c3c") : Color.brandPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 0) {
                    statChip(icon: "ic_star", iconColor: Color.brandTerracotta, value: spot.formattedRating, label: "RATING")
                    if let noise = spot.noiseMatrix?.currentLevel() {
                        dividerLine()
                        statChip(icon: noise.iconName, iconColor: Color.brandPrimary, value: noise.displayName, label: "USUALLY")
                    }
                    if spot.wifiAvailable {
                        dividerLine()
                        statChip(icon: "ic_wifi", iconColor: Color.brandPrimary, value: "Wi-Fi", label: "AVAIL")
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
                            Image("ic_arrow_right")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 13, height: 13)
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
            .padding(.bottom, 24)
        }
    }

    // MARK: - Helpers

    private func loadPodLocations() async {
        podLoadError = nil
        do {
            let pods = try await ReservationAPIClient.shared.pods(accessToken: authService.session?.accessToken)
            var locations: [PodMapLocation] = []
            for pod in pods {
                var request = MKLocalSearch.Request()
                request.naturalLanguageQuery = "\(pod.name), \(pod.address), United Kingdom"
                request.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276),
                    span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.7)
                )
                if let coordinate = try? await MKLocalSearch(request: request).start().mapItems.first?.placemark.coordinate {
                    locations.append(PodMapLocation(pod: pod, coordinate: coordinate))
                }
            }
            podLocations = locations
            if !pods.isEmpty && locations.isEmpty {
                podLoadError = "Pod addresses couldn't be located on the map. You can still book from the Pods tab."
            }
        } catch {
            podLoadError = error.localizedDescription
        }
    }

    private func refreshPodOccupancy() async {
        do {
            let rows: [PodOccupancy] = try await supabase.from("pods")
                .select("id,in_use")
                .execute().value
            podInUse = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.inUse) })
        } catch {
            podOccupancyLog.error("Pod occupancy snapshot failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func watchPodOccupancy() async {
        let channel = supabase.channel("pod-occupancy-\(UUID().uuidString)")
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "pods")
        defer { Task { await supabase.removeChannel(channel) } }
        do {
            try await channel.subscribeWithError()
            await refreshPodOccupancy()
            for await update in updates {
                guard let id = update.record["id"]?.stringValue,
                      let inUse = update.record["in_use"]?.boolValue else { continue }
                podInUse[id] = inUse
            }
        } catch {
            podOccupancyLog.error("Pod occupancy subscription failed: \(error.localizedDescription, privacy: .private)")
            await refreshPodOccupancy()
        }
    }

    private func statChip(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 10, height: 10)
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
            .fill(Color.brandBorder)
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

private struct PodAnnotationView: View {
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image("ic_pod_door")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(hex: "1F3D32"))
                .frame(width: 21, height: 21)
                .padding(10)
                .background(Color.brandTerracotta, in: Capsule())
                .shadow(color: Color.brandTerracotta.opacity(0.25), radius: 8, y: 3)
            Image(systemName: "triangle.fill")
                .font(.system(size: 8))
                .rotationEffect(.degrees(180))
                .foregroundStyle(Color.brandTerracotta)
                .offset(y: -2)
        }
        .scaleEffect(isSelected ? 1.15 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
        .accessibilityLabel("Qwip pod")
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
                                .overlay(Color.brandBorder)
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
                                        icon: level.iconName,
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
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 10, height: 10)
                }
                Text(label)
                    .font(.dmSans(12, weight: .bold))
            }
            .foregroundStyle(isActive ? Color.brandSecondary : Color.brandPrimary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isActive {
            pill
                .background(Capsule().fill(Color.brandPrimary))
        } else {
            pill
        }
    }

    private var pill: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 11, height: 11)
                }
                Text(title.uppercased())
                    .font(.dmSans(10, weight: .black))
                    .tracking(0.5)
            }
            .foregroundStyle(isActive ? Color.brandSecondary : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
