import SwiftUI

struct MapTourOverlay: View {
    var firstPinPosition: CGPoint? = nil
    @AppStorage("hasSeenMapTour") private var hasSeenMapTour = false
    @State private var step = 0

    @Environment(SpotStore.self) private var spotStore
    @Environment(SavedSpotService.self) private var savedSpotService

    var body: some View {
        ZStack {
            if !hasSeenMapTour {
                GeometryReader { geo in
                    ZStack {
                        spotlightMask(geo: geo)
                        if step == 0 {
                            exploreTooltip(geo: geo)
                        } else {
                            saveStep(geo: geo)
                        }
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasSeenMapTour)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    // MARK: - Spotlight

    @ViewBuilder
    private func spotlightMask(geo: GeometryProxy) -> some View {
        if let rect = spotlightRect(geo: geo) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geo.size))
                path.addEllipse(in: rect)
            }
            .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))
        } else {
            Color.black.opacity(0.45)
        }
    }

    private func spotlightRect(geo: GeometryProxy) -> CGRect? {
        guard step == 0 else { return nil }
        let cx = firstPinPosition?.x ?? geo.size.width * 0.5
        let cy = firstPinPosition?.y ?? geo.size.height * 0.35
        let r: CGFloat = 36
        return CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
    }

    // MARK: - Step 0: explore tooltip

    private func exploreTooltip(geo: GeometryProxy) -> some View {
        VStack {
            Spacer().frame(height: geo.size.height * 0.42)
            tooltipCard(
                emoji: "📍",
                headline: "Explore the map",
                body: "Tap any green pin to discover a work-friendly spot near you.",
                buttonLabel: "Next →",
                showDot0: true
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { step = 1 }
            }
            Spacer()
        }
    }

    // MARK: - Step 1: preview card + save tooltip

    private func saveStep(geo: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            // Save spots tooltip in the upper half
            VStack {
                Spacer().frame(height: geo.size.height * 0.28)
                tooltipCard(
                    emoji: "❤️",
                    headline: "Save spots",
                    body: "Tap the heart on any spot to save it. Find all your saved spots in the Saved tab below.",
                    buttonLabel: "Got it ✓",
                    showDot0: false
                ) {
                    withAnimation(.easeInOut(duration: 0.3)) { hasSeenMapTour = true }
                }
                Spacer()
            }

            // Preview card pinned to the bottom, mirroring the real map tile
            if let spot = spotStore.spots.first {
                spotPreviewTile(spot)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Spot preview tile (mirrors MapView.selectedSpotTile)

    private func spotPreviewTile(_ spot: SpotPin) -> some View {
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
                        OpenBadge(isOpen: spot.isOpenNow)
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
            }
            .padding(16)
        }
        .background(glassBackground(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.brandPrimary.opacity(0.15), radius: 20, x: 0, y: 8)
    }

    // MARK: - Shared tooltip card

    private func tooltipCard(
        emoji: String,
        headline: String,
        body: String,
        buttonLabel: String,
        showDot0: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 22))
                Text(headline)
                    .font(.dmSans(15, weight: .heavy))
                    .foregroundStyle(Color.brandSecondary)
            }

            Text(body)
                .font(.dmSans(13))
                .foregroundStyle(Color.brandSecondary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center) {
                Button("Skip tour") {
                    withAnimation(.easeInOut(duration: 0.3)) { hasSeenMapTour = true }
                }
                .font(.dmSans(12, weight: .semibold))
                .foregroundStyle(Color.brandSecondary.opacity(0.4))

                Spacer()

                // Progress dots (2 visible steps)
                HStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { i in
                        let isActive = showDot0 ? i == 0 : i == 1
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isActive ? Color.brandSecondary : Color.brandSecondary.opacity(0.3))
                            .frame(width: isActive ? 14 : 6, height: 3)
                            .animation(.easeInOut(duration: 0.2), value: step)
                    }
                }

                Spacer().frame(width: 12)

                Button(action: action) {
                    Text(buttonLabel)
                        .font(.dmSans(13, weight: .black))
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.brandSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(Color.brandPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.brandPrimary.opacity(0.3), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 24)
    }
}
