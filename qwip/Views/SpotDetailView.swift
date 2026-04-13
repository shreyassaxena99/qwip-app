import SwiftUI
import CoreLocation
import PostHog

struct SpotDetailView: View {
    let detail: SpotDetail
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(LocationService.self) var locationService
    @Environment(\.dismiss) var dismiss
    @State private var currentPhoto = 0
    @State private var showingSaveSheet = false
    @State private var showingShareSheet = false
    @State private var showingMapsSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        actionsRow
                        tagsSection
                        if detail.hasAmenities { amenitiesSection }
                        contactSection
                    }
                    .padding(20)
                    .padding(.bottom, 12)
                }
            }
            .onAppear {
                PostHogSDK.shared.capture("spot_viewed", properties: [
                    "spot_id": detail.id,
                    "spot_name": detail.name,
                    "spot_area": detail.shortAddress ?? ""
                ])
            }
            .background(Color.brandSecondary.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSaveSheet) {
                SaveToCollectionSheet(spot: detail.asSpotPin)
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: [shareText])
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingMapsSheet) {
                MapsPickerSheet(
                    latitude: detail.latitude,
                    longitude: detail.longitude,
                    userLocation: locationService.userLocation?.coordinate
                )
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        let rawPhotos = detail.photos
        let urls = rawPhotos.compactMap { URL(string: $0) }
        if urls.count != rawPhotos.count {
            let dropped = rawPhotos.filter { URL(string: $0) == nil }
            print("[SpotDetailView] \(detail.name): \(dropped.count) photo URL(s) dropped (invalid): \(dropped)")
        }
        return ZStack(alignment: .bottom) {
            if urls.isEmpty {
                let _ = print("[SpotDetailView] \(detail.name): no valid photo URLs — showing gradient hero")
                gradientHero
            } else {
                TabView(selection: $currentPhoto) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        DiagnosticPhotoView(url: url, spotName: detail.name, index: index, fallback: gradientHero)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 240)
                .clipped()

                if urls.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<urls.count, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPhoto
                                      ? Color.brandSecondary
                                      : Color.brandSecondary.opacity(0.45))
                                .frame(width: i == currentPhoto ? 16 : 6, height: 6)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPhoto)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(height: 240)
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().stroke(Color.brandBorder, lineWidth: 1))
                            .frame(width: 32, height: 32)
                        Image("ic_x")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 11, height: 11)
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button { showingSaveSheet = true } label: {
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
                            .foregroundStyle(savedSpotService.isSaved(detail.id) ? Color(hex: "e74c3c") : Color.brandPrimary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    private var gradientHero: some View {
        ZStack {
            LinearGradient(
                colors: [Color.brandPrimary, Color.brandPrimary.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 240)

            Circle()
                .fill(Color.brandSecondary.opacity(0.08))
                .frame(width: 160)
                .offset(x: -80, y: 40)
                .blur(radius: 20)

            Circle()
                .fill(Color.brandSecondary.opacity(0.12))
                .frame(width: 100)
                .offset(x: 100, y: -30)
                .blur(radius: 15)

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(Color.brandSecondary.opacity(0.3), lineWidth: 1.5))
                        .frame(width: 80, height: 80)
                        .shadow(color: Color.brandPrimary.opacity(0.3), radius: 12, x: 0, y: 4)
                    Image(detail.category.iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Color.brandSecondary)
                }
                Text(detail.category.displayName.uppercased())
                    .font(.dmSans(10, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Color.brandSecondary.opacity(0.7))
            }
        }
        .clipped()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(detail.name)
                    .font(.dmSans(26, weight: .heavy))
                    .foregroundStyle(Color.brandPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                OpenBadge(isOpen: detail.isOpenNow)
                    .padding(.top, 4)
            }

            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image("ic_star")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 11, height: 11)
                        .foregroundStyle(.orange)
                    Text(detail.formattedRating)
                        .font(.dmSans(14, weight: .heavy))
                        .foregroundStyle(Color.brandPrimary)
                    if let count = detail.userRatingCount {
                        Text("(\(count))")
                            .font(.dmSans(12, weight: .medium))
                            .foregroundStyle(Color.brandPrimary.opacity(0.5))
                    }
                }
                dot()
                Text(detail.accessType.displayName)
                    .font(.dmSans(13, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary.opacity(0.6))
            }

            if let desc = detail.displayDescription, !desc.isEmpty {
                Text(desc)
                    .font(.dmSans(15))
                    .foregroundStyle(Color.brandPrimary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .background(glassBackground(cornerRadius: 18))
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Details")
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 8
            ) {
                TagChip(icon: "ic_wifi", label: detail.wifiAvailable ? "Wi-Fi" : "No Wi-Fi",
                        active: detail.wifiAvailable)
                TagChip(icon: "ic_plug_zap", label: detail.powerOutlets ? "Power" : "No Power",
                        active: detail.powerOutlets)
                if let noise = detail.noiseMatrix?.currentLevel(),
                   let text = detail.noiseMatrix?.currentDisplayText() {
                    TagChip(icon: noise.iconName, label: text, active: true)
                }
                TagChip(icon: detail.accessType.iconName, label: detail.accessType.displayName,
                        active: true)
            }
        }
        .padding(18)
        .background(glassBackground(cornerRadius: 18))
    }

    // MARK: - Amenities

    private var amenitiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Amenities")
            FlowLayout(spacing: 8) {
                if detail.outdoorSeating == true { AmenityChip(icon: "ic_sun",       label: "Outdoor Seating") }
                if detail.allowsDogs == true     { AmenityChip(icon: "ic_paw_print", label: "Dog Friendly") }
                if detail.servesCoffee == true   { AmenityChip(icon: "ic_coffee",    label: "Coffee") }
                if detail.goodForGroups == true  { AmenityChip(icon: "ic_users",     label: "Good for Groups") }
            }
        }
        .padding(18)
        .background(glassBackground(cornerRadius: 18))
    }

    // MARK: - Contact

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Info")
            if let address = detail.displayAddress {
                ContactRow(icon: "ic_map_pin", text: address, url: nil)
            }
            if let phone = detail.phoneNational {
                Divider().overlay(Color.brandBorder)
                ContactRow(
                    icon: "ic_phone",
                    text: phone,
                    url: URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))")
                )
            }
            if let website = detail.websiteUri, let url = URL(string: website) {
                Divider().overlay(Color.brandBorder)
                let display = website
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                ContactRow(icon: "ic_globe", text: display, url: url)
            }
        }
        .padding(18)
        .background(glassBackground(cornerRadius: 18))
    }

    // MARK: - Actions Row

    private var actionsRow: some View {
        HStack(spacing: 12) {

            // Share
            Button {
                PostHogSDK.shared.capture("spot_shared", properties: [
                    "spot_id": detail.id,
                    "spot_name": detail.name,
                    "spot_area": detail.shortAddress ?? ""
                ])
                showingShareSheet = true
            } label: {
                VStack(spacing: 7) {
                    Image("ic_share_2")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color.brandPrimary)
                    Text("Share")
                        .font(.dmSans(12, weight: .bold))
                        .foregroundStyle(Color.brandPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(glassBackground(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Directions
            Button {
                PostHogSDK.shared.capture("spot_directions_tapped", properties: [
                    "spot_id": detail.id,
                    "spot_name": detail.name,
                    "spot_area": detail.shortAddress ?? ""
                ])
                showingMapsSheet = true
            } label: {
                VStack(spacing: 7) {
                    Image("ic_route")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color.brandSecondary)
                    Text("Directions")
                        .font(.dmSans(12, weight: .bold))
                        .foregroundStyle(Color.brandSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.brandPrimary)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.brandPrimary.opacity(0.4), radius: 12, x: 0, y: 5)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var shareText: String {
        var lines = [detail.name]
        if let address = detail.displayAddress { lines.append(address) }
        let lat = String(format: "%.4f", detail.latitude)
        let lon = String(format: "%.4f", detail.longitude)
        lines.append("https://maps.google.com/?q=\(lat),\(lon)")
        return lines.joined(separator: "\n")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.dmSans(10, weight: .black))
            .tracking(1.2)
            .foregroundStyle(Color.brandPrimary.opacity(0.5))
    }

    private func dot() -> some View {
        Text("·").foregroundStyle(Color.brandPrimary.opacity(0.3))
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Maps Picker Sheet

private struct MapsPickerSheet: View {
    let latitude: Double
    let longitude: Double
    let userLocation: CLLocationCoordinate2D?
    @Environment(\.dismiss) private var dismiss

    private struct MapApp {
        let name: String
        let icon: String
        let url: URL
    }

    private var availableApps: [MapApp] {
        var apps: [MapApp] = []
        let lat = latitude, lng = longitude

        if let url = URL(string: "comgooglemaps://?daddr=\(lat),\(lng)&directionsmode=driving"),
           UIApplication.shared.canOpenURL(url) {
            apps.append(MapApp(name: "Google Maps", icon: "map", url: url))
        }
        if let url = URL(string: "waze://?ll=\(lat),\(lng)&navigate=yes"),
           UIApplication.shared.canOpenURL(url) {
            apps.append(MapApp(name: "Waze", icon: "car.fill", url: url))
        }
        if let url = URL(string: "citymapper://directions?endcoord=\(lat),\(lng)"),
           UIApplication.shared.canOpenURL(url) {
            apps.append(MapApp(name: "Citymapper", icon: "tram.fill", url: url))
        }
        var appleURLString = "maps://?daddr=\(lat),\(lng)&dirflg=d"
        if let loc = userLocation {
            appleURLString += "&saddr=\(loc.latitude),\(loc.longitude)"
        }
        if let url = URL(string: appleURLString) {
            apps.append(MapApp(name: "Apple Maps", icon: "map.fill", url: url))
        }
        return apps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Open with")
                .font(.dmSans(18, weight: .black))
                .foregroundStyle(Color.brandPrimary)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 20)

            VStack(spacing: 0) {
                ForEach(availableApps, id: \.name) { app in
                    Button {
                        UIApplication.shared.open(app.url)
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.brandPrimary.opacity(0.08))
                                    .frame(width: 40, height: 40)
                                Image(systemName: app.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.brandPrimary)
                            }
                            Text(app.name)
                                .font(.dmSans(15, weight: .semibold))
                                .foregroundStyle(Color.brandPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.brandPrimary.opacity(0.3))
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .background(Color.brandSecondary.ignoresSafeArea())
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let icon: String
    let label: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 11, height: 11)
                .foregroundStyle(active ? Color.brandPrimary : Color.brandPrimary.opacity(0.35))
            Text(label)
                .font(.dmSans(12, weight: .bold))
                .foregroundStyle(active ? Color.brandPrimary : Color.brandPrimary.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? Color.brandPrimary.opacity(0.08) : Color.brandPrimary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.brandPrimary.opacity(active ? 0.15 : 0.07), lineWidth: 1)
                )
        )
    }
}

// MARK: - Amenity Chip

struct AmenityChip: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 11, height: 11)
            Text(label)
                .font(.dmSans(12, weight: .bold))
        }
        .foregroundStyle(Color.brandPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.brandPrimary.opacity(0.08))
                .overlay(Capsule().stroke(Color.brandPrimary.opacity(0.15), lineWidth: 1))
        )
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let icon: String
    let text: String
    let url: URL?

    var body: some View {
        Group {
            if let url {
                Link(destination: url) { rowContent(tappable: true) }
            } else {
                rowContent(tappable: false)
            }
        }
    }

    private func rowContent(tappable: Bool) -> some View {
        HStack(spacing: 10) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 24)
            Text(text)
                .font(.dmSans(14, weight: .medium))
                .foregroundStyle(tappable ? Color.brandPrimary : Color.brandPrimary.opacity(0.7))
                .underline(tappable)
                .lineLimit(2)
            if tappable {
                Spacer()
                Image("ic_arrow_up_right")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(Color.brandPrimary.opacity(0.4))
            }
        }
    }
}

// MARK: - Diagnostic Photo View

/// Fetches a photo URL via URLSession so we can log the actual HTTP status on failure.
private struct DiagnosticPhotoView<Fallback: View>: View {
    let url: URL
    let spotName: String
    let index: Int
    let fallback: Fallback

    @State private var image: UIImage? = nil
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                fallback
                    .task {
                        await load()
                    }
            }
        }
    }

    private func load() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[DiagnosticPhotoView] \(spotName) photo[\(index)] — HTTP \(status) — \(url)")
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? "<binary>"
                print("[DiagnosticPhotoView] \(spotName) photo[\(index)] error body: \(body)")
                failed = true
                return
            }
            guard let img = UIImage(data: data) else {
                print("[DiagnosticPhotoView] \(spotName) photo[\(index)] — data not decodable as image (\(data.count) bytes)")
                failed = true
                return
            }
            image = img
        } catch {
            print("[DiagnosticPhotoView] \(spotName) photo[\(index)] — network error: \(error.localizedDescription)")
            failed = true
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width, rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
