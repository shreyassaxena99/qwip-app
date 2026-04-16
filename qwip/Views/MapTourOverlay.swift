import SwiftUI

struct MapTourOverlay: View {
    var firstPinPosition: CGPoint? = nil
    @AppStorage("hasSeenMapTour") private var hasSeenMapTour = false
    @State private var step = 0

    @Environment(SpotStore.self) private var spotStore
    @Environment(SavedSpotService.self) private var savedSpotService
    @Environment(LocationService.self) private var locationService

    @State private var tourDetailSpot: SpotDetail? = nil
    @State private var isFetchingTourSpot = false

    var body: some View {
        ZStack {
            if !hasSeenMapTour {
                GeometryReader { geo in
                    ZStack {
                        spotlightMask(geo: geo)
                        tooltipCard(geo: geo)
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasSeenMapTour)
        .onChange(of: step) { _, newStep in
            if newStep == 1 { tryOpenTourSpot() }
        }
        .onChange(of: spotStore.spots) { _, spots in
            // Retry once spots load in case they weren't ready when step became 1
            if step == 1 && !spots.isEmpty && tourDetailSpot == nil && !isFetchingTourSpot {
                tryOpenTourSpot()
            }
        }
        .sheet(item: $tourDetailSpot, onDismiss: {
            withAnimation(.easeInOut(duration: 0.2)) { step = 2 }
        }) { detail in
            SpotDetailView(detail: detail)
                .environment(savedSpotService)
                .environment(locationService)
        }
    }

    // MARK: - Tour spot fetch

    private func tryOpenTourSpot() {
        guard let firstSpot = spotStore.spots.first, !isFetchingTourSpot else { return }
        isFetchingTourSpot = true
        Task {
            defer { isFetchingTourSpot = false }
            tourDetailSpot = try? await SpotAPIClient.shared.fetchSpotDetail(id: firstSpot.id)
            if tourDetailSpot == nil {
                // Fetch failed — skip spot detail step and continue tour
                withAnimation(.easeInOut(duration: 0.2)) { step = 2 }
            }
        }
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

    /// Returns the spotlight cutout rect for the current step, or nil for a full dim.
    private func spotlightRect(geo: GeometryProxy) -> CGRect? {
        switch step {
        case 0:
            // Use the actual position of the first rendered pin, falling back to
            // an approximate centre-of-map position if pins haven't loaded yet.
            let cx = firstPinPosition?.x ?? geo.size.width * 0.5
            let cy = firstPinPosition?.y ?? geo.size.height * 0.35
            let r: CGFloat = 36
            return CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        default:
            return nil
        }
    }

    // MARK: - Tooltip card

    @ViewBuilder
    private func tooltipCard(geo: GeometryProxy) -> some View {
        if step == 1 {
            // Step 1: opening spot detail sheet — show spinner while fetching
            if isFetchingTourSpot {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                    Spacer()
                }
            }
            // Once the sheet opens we're behind it — nothing else needed here
        } else {
            let config = stepConfigs[step == 0 ? 0 : 1] // step 0 → index 0, step 2 → index 1

            VStack {
                Spacer().frame(height: step == 0
                               ? geo.size.height * 0.42   // below spotlight
                               : geo.size.height * 0.28)  // step 2: centred

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(config.emoji)
                            .font(.system(size: 22))
                        Text(config.headline)
                            .font(.dmSans(15, weight: .heavy))
                            .foregroundStyle(Color.brandSecondary)
                    }

                    Text(config.body)
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

                        // Progress dots (3 total, step 1 is the sheet)
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(i == step
                                          ? Color.brandSecondary
                                          : Color.brandSecondary.opacity(0.3))
                                    .frame(width: i == step ? 14 : 6, height: 3)
                                    .animation(.easeInOut(duration: 0.2), value: step)
                            }
                        }

                        Spacer().frame(width: 12)

                        Button {
                            if step == 0 {
                                withAnimation(.easeInOut(duration: 0.2)) { step = 1 }
                            } else {
                                withAnimation(.easeInOut(duration: 0.3)) { hasSeenMapTour = true }
                            }
                        } label: {
                            Text(step == 0 ? "Next →" : "Got it ✓")
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

                Spacer()
            }
        }
    }

    // MARK: - Step content (steps 0 and 2 only — step 1 opens a sheet)

    private struct StepConfig {
        let emoji: String
        let headline: String
        let body: String
    }

    private let stepConfigs: [StepConfig] = [
        StepConfig(
            emoji: "📍",
            headline: "Explore the map",
            body: "Tap any green pin to discover a work-friendly spot near you."
        ),
        StepConfig(
            emoji: "❤️",
            headline: "Save spots",
            body: "Tap the heart on any spot to save it. Find all your saved spots in the Saved tab below."
        ),
    ]
}
