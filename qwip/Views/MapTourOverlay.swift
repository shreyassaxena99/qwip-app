import SwiftUI

struct MapTourOverlay: View {
    @AppStorage("hasSeenMapTour") private var hasSeenMapTour = false
    @State private var step = 0

    var body: some View {
        if !hasSeenMapTour {
            GeometryReader { geo in
                ZStack {
                    spotlightMask(geo: geo)
                    tooltipCard(geo: geo)
                }
            }
            .ignoresSafeArea()
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
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
            // Circular spotlight over the pin cluster area (upper-centre of map)
            let cx = geo.size.width * 0.5
            let cy = geo.size.height * 0.3
            let r: CGFloat = 36
            return CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        default:
            // Steps 1 and 2: full dim, tooltip only
            return nil
        }
    }

    // MARK: - Tooltip card

    @ViewBuilder
    private func tooltipCard(geo: GeometryProxy) -> some View {
        let config = stepConfigs[step]

        VStack {
            if step == 0 {
                // Below spotlight — leave room for the pin area in upper 30%
                Spacer().frame(height: geo.size.height * 0.42)
            } else if step == 1 {
                // Upper area — map content below
                Spacer().frame(height: geo.size.height * 0.12)
            } else {
                // Step 2: centred
                Spacer().frame(height: geo.size.height * 0.28)
            }

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
                        withAnimation { hasSeenMapTour = true }
                    }
                    .font(.dmSans(12, weight: .semibold))
                    .foregroundStyle(Color.brandSecondary.opacity(0.4))

                    Spacer()

                    // Progress dots
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
                        if step < 2 {
                            withAnimation { step += 1 }
                        } else {
                            withAnimation { hasSeenMapTour = true }
                        }
                    } label: {
                        Text(step < 2 ? "Next →" : "Got it ✓")
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

    // MARK: - Step content

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
            emoji: "☕",
            headline: "Spot details",
            body: "Tap a pin to see opening hours, wifi quality, noise level, and directions."
        ),
        StepConfig(
            emoji: "❤️",
            headline: "Save spots",
            body: "Tap the heart on any spot to save it. Find all your saved spots in the Saved tab below."
        ),
    ]
}
