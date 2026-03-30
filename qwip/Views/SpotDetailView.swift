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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSaveSheet = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().stroke(Color.brandPrimary.opacity(0.12), lineWidth: 1))
                                .frame(width: 32, height: 32)
                            Image(systemName: savedSpotService.isSaved(detail.id) ? "heart.fill" : "heart")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(savedSpotService.isSaved(detail.id) ? Color(hex: "e74c3c") : Color.brandPrimary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSaveSheet) {
                SaveToCollectionSheet(spot: detail.asSpotPin)
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: [shareText])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        let urls = detail.photos.compactMap { URL(string: $0) }
        return ZStack(alignment: .bottom) {
            if urls.isEmpty {
                gradientHero
            } else {
                TabView(selection: $currentPhoto) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                gradientHero
                            }
                        }
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
                    Image(systemName: detail.category.systemIcon)
                        .font(.system(size: 34, weight: .semibold))
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
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
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
                TagChip(icon: "wifi", label: detail.wifiAvailable ? "Wi-Fi" : "No Wi-Fi",
                        active: detail.wifiAvailable)
                TagChip(icon: "powerplug.fill", label: detail.powerOutlets ? "Power" : "No Power",
                        active: detail.powerOutlets)
                if let noise = detail.noiseMatrix?.currentLevel(),
                   let text = detail.noiseMatrix?.currentDisplayText() {
                    TagChip(icon: noise.systemIcon, label: text, active: true)
                }
                TagChip(icon: detail.accessType.systemIcon, label: detail.accessType.displayName,
                        active: detail.accessType == .free)
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
                if detail.outdoorSeating == true { AmenityChip(icon: "sun.max.fill", label: "Outdoor Seating") }
                if detail.allowsDogs == true     { AmenityChip(icon: "pawprint.fill", label: "Dog Friendly") }
                if detail.servesCoffee == true   { AmenityChip(icon: "cup.and.saucer.fill", label: "Coffee") }
                if detail.goodForGroups == true  { AmenityChip(icon: "person.3.fill", label: "Good for Groups") }
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
                ContactRow(icon: "mappin.circle.fill", text: address, url: nil)
            }
            if let phone = detail.phoneNational {
                Divider().overlay(Color.brandPrimary.opacity(0.08))
                ContactRow(
                    icon: "phone.circle.fill",
                    text: phone,
                    url: URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))")
                )
            }
            if let website = detail.websiteUri, let url = URL(string: website) {
                Divider().overlay(Color.brandPrimary.opacity(0.08))
                let display = website
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                ContactRow(icon: "globe.americas.fill", text: display, url: url)
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
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 22, weight: .semibold))
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
                var urlString = "maps://?daddr=\(detail.latitude),\(detail.longitude)&dirflg=d"
                if let loc = locationService.userLocation {
                    urlString += "&saddr=\(loc.coordinate.latitude),\(loc.coordinate.longitude)"
                }
                if let url = URL(string: urlString) { UIApplication.shared.open(url) }
            } label: {
                VStack(spacing: 7) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 22, weight: .semibold))
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

// MARK: - Tag Chip

struct TagChip: View {
    let icon: String
    let label: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
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
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
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
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 24)
            Text(text)
                .font(.dmSans(14, weight: .medium))
                .foregroundStyle(tappable ? Color.brandPrimary : Color.brandPrimary.opacity(0.7))
                .underline(tappable)
                .lineLimit(2)
            if tappable {
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.brandPrimary.opacity(0.4))
            }
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
